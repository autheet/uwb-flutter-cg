package net.christiangreiner.uwb

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.uwb.RangingParameters
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbAddress
import androidx.core.uwb.UwbComplexChannel
import androidx.core.uwb.UwbControllerSessionScope
import androidx.core.uwb.UwbManager
import androidx.core.uwb.rxjava3.controllerSessionScopeSingle
import androidx.core.uwb.rxjava3.rangingResultsFlowable
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.reactivex.rxjava3.disposables.Disposable

private fun Throwable.toFlutterError(): FlutterError {
    return FlutterError("NATIVE_ERROR", this.message, this.stackTraceToString())
}

class UwbPlugin : FlutterPlugin, ActivityAware, UwbHostApi {
    private val logTag = "UwbPlugin"
    private val requestCode = 1337

    private var activity: Activity? = null
    private lateinit var uwbManager: UwbManager
    private lateinit var flutterApi: UwbFlutterApi

    private var controllerSessionScope: UwbControllerSessionScope? = null
    private var rangingJob: Disposable? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = UwbFlutterApi(binding.binaryMessenger)
        uwbManager = UwbManager.createInstance(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, null)
        stopUwbSessions()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun isUwbSupported(): Boolean {
        return uwbManager.isAvailable
    }

    override fun getLocalUwbAddress(callback: (Result<ByteArray>) -> Unit) {
        if (controllerSessionScope != null) {
            callback(Result.success(controllerSessionScope!!.localAddress.address))
            return
        }
        val sessionScopeSingle = uwbManager.controllerSessionScopeSingle()
        sessionScopeSingle.subscribe({ scope ->
            controllerSessionScope = scope
            callback(Result.success(scope.localAddress.address))
        }, { error ->
            Log.e(logTag, "Failed to get local UWB address", error)
            callback(Result.failure(error.toFlutterError()))
        })
    }

    override fun startRanging(peerAddress: ByteArray, config: UwbSessionConfig) {
        val scope = controllerSessionScope ?: run {
            Log.e(logTag, "Ranging failed: UWB session not initialized. Call getLocalUwbAddress first.")
            return
        }

        try {
            val rangingParameters = RangingParameters(
                uwbConfigType = RangingParameters.CONFIG_UNICAST_DS_TWR,
                sessionId = config.sessionId.toInt(),
                subSessionId = 0,
                sessionKeyInfo = config.sessionKeyInfo,
                subSessionKeyInfo = null,
                complexChannel = UwbComplexChannel(config.channel, config.preambleIndex.toInt()),
                peerDevices = listOf(androidx.core.uwb.UwbDevice(UwbAddress(peerAddress))),
                updateRateType = RangingParameters.RANGING_UPDATE_RATE_AUTOMATIC,
            )

            rangingJob = scope.rangingResultsFlowable(rangingParameters)
                .subscribe({ rangingResult ->
                    handleRangingResult(rangingResult, peerAddress)
                }, { error ->
                    Log.e(logTag, "Ranging subscription error", error)
                    flutterApi.onRangingError(error.toFlutterError()) {}
                })
        } catch (e: Exception) {
            Log.e(logTag, "Failed to start ranging", e)
        }
    }

    private fun handleRangingResult(rangingResult: RangingResult, peerAddressBytes: ByteArray) {
        val device = UwbDevice(address = peerAddressBytes)
        when (rangingResult) {
            is RangingResult.RangingResultPosition -> {
                val position = rangingResult.position
                val data = UwbRangingData(
                    distance = position.distance?.value?.toDouble(),
                    azimuth = position.azimuth?.value?.toDouble(),
                    elevation = position.elevation?.value?.toDouble(),
                    direction = null,
                    horizontalAngle = null
                )
                flutterApi.onRangingResult(device, data) {}
            }
            is RangingResult.RangingResultPeerDisconnected -> {
                flutterApi.onPeerDisconnected(device) {}
            }
        }
    }

    override fun stopRanging(peerAddress: String) {
        // This is tricky because we only have the byte array address.
        // For now, since we only support one session, we can just stop the current one.
        rangingJob?.dispose()
        rangingJob = null
    }

    override fun stopUwbSessions() {
        rangingJob?.dispose()
        rangingJob = null
        controllerSessionScope?.close()
        controllerSessionScope = null
    }
}
