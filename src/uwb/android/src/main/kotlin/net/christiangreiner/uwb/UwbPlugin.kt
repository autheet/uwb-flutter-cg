package net.christiangreiner.uwb

import UwbData
import UwbDevice
import UwbFlutterApi
import UwbHostApi
import UwbSessionConfig
import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbAddress
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import net.christiangreiner.uwb.oob.UwbConfig

/** UwbPlugin */
class UwbPlugin : FlutterPlugin, UwbHostApi, ActivityAware {

    companion object {
      lateinit var flutterApi: UwbFlutterApi
        private set
    }

    private val coroutineScope = CoroutineScope(Dispatchers.Main + Job())

    // Android Stuff
    private val LOG_TAG: String = "UWB Plugin"
    private var appContext: Context? = null
    private var appActivity: Activity? = null
    private lateinit var packageManager: PackageManager
    private lateinit var uwbConnectionManager: UwbConnectionManager
    private lateinit var uwbDataHandler: UwbDataHandler
    private var REQUIRED_PERMISSIONS: Array<String> = arrayOf()

    private fun detectRequiredPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            REQUIRED_PERMISSIONS = arrayOf<String>(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_ADVERTISE,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.NEARBY_WIFI_DEVICES,
                Manifest.permission.UWB_RANGING
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            REQUIRED_PERMISSIONS = arrayOf<String>(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_ADVERTISE,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.UWB_RANGING
            )
        } else {
             REQUIRED_PERMISSIONS = arrayOf<String>(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.UWB_RANGING
            )
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        packageManager = flutterPluginBinding.applicationContext.packageManager

        UwbHostApi.setUp(flutterPluginBinding.binaryMessenger, this)
        flutterApi = UwbFlutterApi(flutterPluginBinding.binaryMessenger)

        val uwbDataEventChannel =
            EventChannel(flutterPluginBinding.binaryMessenger, "uwb_plugin/uwbData")

        this.uwbDataHandler = UwbDataHandler()
        uwbDataEventChannel.setStreamHandler(uwbDataHandler)

        this.uwbConnectionManager = UwbConnectionManager(appContext!!, coroutineScope)
        detectRequiredPermissions()
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.appActivity = binding.activity
    }

    override fun onDetachedFromActivity() {
        this.appActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        this.appActivity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        this.appActivity = null
    }

    private fun hasPermissions(context: Context, permissions: Array<String>): Boolean {
        for (permission in permissions) {
            if (ContextCompat.checkSelfPermission(context, permission) != PackageManager.PERMISSION_GRANTED) {
                return false
            }
        }
        return true
    }

    private fun uwbSupported(): Boolean {
        return packageManager.hasSystemFeature("android.hardware.uwb")
    }

    override fun getLocalUwbAddress(callback: (Result<ByteArray>) -> Unit) {
        if (!hasPermissions(appContext!!, REQUIRED_PERMISSIONS)) {
            flutterApi.onPermissionRequired(PermissionAction.REQUEST) {}
            callback(Result.failure(Exception("Permissions not granted.")))
            return
        }
        uwbConnectionManager.createControllerSession()
        callback(Result.success(uwbConnectionManager.localUwbAddress!!.address))
    }

    override fun isUwbSupported(): Boolean {
        return this.uwbSupported()
    }

    override fun startRanging(peerAddress: ByteArray, config: UwbSessionConfig) {
        val uwbAddress = UwbAddress(peerAddress)
        val nativeConfig = UwbConfig(
            preambleIndex = config.preambleIndex.toInt(),
            sessionKey = config.sessionId.toInt(),
            uwbAddress = uwbAddress.address
        )
        coroutineScope.launch {
            uwbConnectionManager.startRanging(String(peerAddress), uwbAddress, nativeConfig).collect { rangingResult ->
                onRangingResult(String(peerAddress), rangingResult)
            }
        }
    }
    
    override fun stopRanging(peerAddress: String) {
        this.uwbConnectionManager.stopRanging(peerAddress)
    }

    override fun stopUwbSessions() {
        this.uwbConnectionManager.stopRanging()
    }

    private fun onRangingResult(peerAddress: String, rangingResult: RangingResult) {
        when (rangingResult) {
            is RangingResult.RangingResultPosition -> {
                val distance = rangingResult.position.distance?.value ?: 0f
                val elevation = rangingResult.position.elevation?.value ?: 0f
                val azimuth = rangingResult.position.azimuth?.value ?: 0f

                val uwbDevice = UwbDevice(
                    id = peerAddress,
                    name = "",
                    uwbData = UwbData(
                        distance = distance.toDouble(),
                        elevation = elevation.toDouble(),
                        azimuth = azimuth.toDouble(),
                    ),
                    deviceType = DeviceType.SMARTPHONE
                )
                flutterApi.onRanging(uwbDevice) {}
            }
            is RangingResult.RangingResultPeerDisconnected -> {
                Log.e(LOG_TAG, "Ranging result peer disconnected: ${rangingResult.device.address}")
                this.uwbConnectionManager.stopRanging(peerAddress)
            }
            else -> {
                Log.e(LOG_TAG, "Unexpected ranging result type")
            }
        }
    }
}
