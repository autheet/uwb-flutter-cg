package net.christiangreiner.uwb

import DeviceState
import DeviceType
import ErrorCode
import FlutterError
import UwbData
import UwbDevice
import UwbFlutterApi
import UwbHostApi
import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbAddress
import androidx.core.uwb.UwbManager
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.Status
import com.google.android.gms.nearby.connection.ConnectionsStatusCodes
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.tasks.Task
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import net.christiangreiner.uwb.oob.Endpoint
import net.christiangreiner.uwb.oob.NearbyManager
import net.christiangreiner.uwb.oob.UwbConfig
import kotlin.random.Random


/** UwbPlugin */
class UwbPlugin : FlutterPlugin, UwbHostApi, ActivityAware {

    companion object {
      lateinit var flutterApi: UwbFlutterApi
        private set
    }

    private val mainScope = CoroutineScope(Dispatchers.Main)
    private val coroutineScope = CoroutineScope(
        Dispatchers.IO +
                Job() +
                CoroutineExceptionHandler { _, e -> Log.e(LOG_TAG, "Connection Error", e) }
    )

    // Android Stuff
    private val LOG_TAG: String = "UWB Plugin"
    private var appContext: Context? = null
    private var appActivity: Activity? = null
    private lateinit var packageManager: PackageManager

    private val REQUEST_CODE_REQUIRED_PERMISSIONS = 1

    private lateinit var uwbConnectionManager: UwbConnectionManager
    private lateinit var nearbyManager: NearbyManager
    private lateinit var uwbDataHandler: UwbDataHandler

    private var isController: Boolean = false
    private var peerUwbAddress: UwbAddress? = null
    private var preambleIndex: Int = -1
    private var sessionKey: Int = 0


    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        packageManager = flutterPluginBinding.applicationContext.packageManager

        UwbHostApi.setUp(flutterPluginBinding.binaryMessenger, this)
        flutterApi = UwbFlutterApi(flutterPluginBinding.binaryMessenger)

        var uwbDataEventChannel =
            EventChannel(flutterPluginBinding.binaryMessenger, "uwb_plugin/uwbData")

        this.uwbDataHandler = UwbDataHandler()
        uwbDataEventChannel.setStreamHandler(uwbDataHandler)

        this.uwbConnectionManager = UwbConnectionManager(appContext!!, coroutineScope)
        this.uwbConnectionManager.onUwbRangingStarted = onUwbRangingStartedCallback

    }

    private fun getAppLabel(context: Context): String {
        return context.applicationInfo.nonLocalizedLabel.toString()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, null)
    }

    private fun uwbSupported(): Boolean {
        return packageManager.hasSystemFeature("android.hardware.uwb")
    }

    // Flutter API
    override fun startRanging(device: UwbDevice, callback: (Result<Unit>) -> Unit) {
        Log.d(LOG_TAG, "Start Ranging with ${device.name}. Connect to endpoint ${device.id}")

        if(uwbConnectionManager.isRanging()) {
            callback(Result.failure(FlutterError("Device already ranging")))
            return
        }

        // Device likes to be the controller
        this.isController = true

    }

    // Flutter API

    // Flutter API
    override fun stopUwbSessions(callback: (Result<Unit>) -> Unit) {
        this.uwbConnectionManager.stopRanging()
        this.nearbyManager.disconnectFromAll()
        this.isController = false

        // Restart Discovery so disconnected devices found again
        this.nearbyManager.restartDiscovery()
        this.isController = false
        callback(Result.success(Unit))
    }

    // Flutter API
    override fun isUwbSupported(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(value = this.uwbSupported()))
    }

    // Flutter API

    private fun hasPermissions(context: Context, permissions: Array<String>): Boolean {
        for (permission in permissions) {
            if (ContextCompat.checkSelfPermission(context, permission) != PackageManager.PERMISSION_GRANTED) {
                return false
            }
        }
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.appActivity = binding.activity
    }

    /**
     * As soon as the other endpoint is connected the devices shares their uwb parameters.
     */
    private val onEndpointConnectedCallback: (Endpoint) -> Unit = { endpoint ->
        Log.d(LOG_TAG , "(onEndpointConnectedCallback) Endpoint connected: $endpoint")

        flutterApi.onHostDiscoveryDeviceConnected(

        shareUwbParameters(endpoint)
    }

    private fun shareUwbParameters(endpoint: Endpoint) {
        var payloadToSend: Payload? = null
        if (isController) {
            val preamble = uwbConnectionManager.getControllerSessionScope()!!.uwbComplexChannel.preambleIndex
            val addressBytes: ByteArray = uwbConnectionManager.localUwbAddress!!.address
            this.preambleIndex = preamble
            this.sessionKey = Random.nextInt(1000, 9999)
            val config = UwbConfig(1, preamble, sessionKey, addressBytes)
            Log.i(LOG_TAG, "Session Key: $sessionKey")
            payloadToSend = Payload.fromBytes(config.toByteArray())
        } else {
            val addressBytes: ByteArray = uwbConnectionManager.localUwbAddress!!.address
            var data = UwbConfig(0, -1, 0, addressBytes)
            payloadToSend = Payload.fromBytes(data.toByteArray())
        }

        if (payloadToSend != null) {
            Log.i(LOG_TAG, "(shareUwbData) Sending payload")
            nearbyManager.sendData(endpoint, payloadToSend)
        }

    }

    private val onPayloadReceivedCallback: (Endpoint, ByteArray) -> Unit = { endpoint, byteArray ->
        Log.d(LOG_TAG, "(onPayloadReceivedCallback) Payload received by ${endpoint.id}")

        // TODO: Identify the type of payload
        // 0: UwbConfig
        // 1: Other stuff

        var uwbConfigData = UwbConfig.fromByteArray(byteArray)

        peerUwbAddress  = UwbAddress(uwbConfigData.uwbAddress)
        var currentPreamble: Int = 0
        var currentSessionKey: Int = 0

        if (isController) {
            // TODO: Move this in a temp map to avoid race conditions
            currentPreamble = this.preambleIndex
            currentSessionKey = this.sessionKey
        } else {
            currentPreamble = uwbConfigData.preambleIndex
            currentSessionKey = uwbConfigData.sessionKey
        }

        if (!uwbConnectionManager.isRanging()) {
            mainScope.launch  {
                uwbConnectionManager.startRanging(endpoint.id, peerUwbAddress!!, currentSessionKey, currentPreamble).collect {
                        rangingResult -> onRangingResult(endpoint, rangingResult)
                }
            }
        }
    }

    private fun onRangingResult(endpoint: Endpoint, rangingResult: RangingResult) {
        when (rangingResult) {
            is RangingResult.RangingResultPosition -> {
                val distance = rangingResult.position.distance?.value ?: 0f
                val elevation = rangingResult.position.elevation?.value ?: 0f
                val azimuth = rangingResult.position.azimuth?.value ?: 0f

                // Send data to Flutter
                var uwbDevice = UwbDevice(
                    id = endpoint.id,
                    name = endpoint.name,
                    uwbData = UwbData(
                        distance = distance.toDouble(),
                        elevation = elevation.toDouble(),
                        azimuth = azimuth.toDouble(),
                    ),
                    deviceType = DeviceType.SMARTPHONE,
                    state = DeviceState.RANGING
                )
                uwbDataHandler.sendData(uwbDevice)
            }
            is RangingResult.RangingResultPeerDisconnected -> {
                Log.e(LOG_TAG, "Ranging result peer disconnected: ${rangingResult.device.address}")


                // reset flag so this device it could be a controlee
                this.isController = false

                flutterApi.onHostUwbSessionDisconnected(
                    createUwbDevice(endpoint)
                ) {Result.success(it)}
            }
            else -> {
                Log.e(LOG_TAG, "Unexpected ranging result type")
            }
        }
    }


    private val onUwbRangingStartedCallback: (String) -> Unit = { endpointId ->
        Log.d(LOG_TAG, "(onUwbRangingStartedCallback) Ranging started with: $endpointId")
        if (this.nearbyManager.getConnectedEndpoints().containsKey(endpointId)) {
            var device = this.nearbyManager.getConnectedEndpoints()[endpointId]!!

            flutterApi.onHostUwbSessionStarted(
                createUwbDevice(device)
            ) {Result.success(it)}
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {}

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}

    override fun onDetachedFromActivity() {}
}