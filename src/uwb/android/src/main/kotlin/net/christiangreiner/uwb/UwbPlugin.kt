package net.christiangreiner.uwb

import android.Manifest
import android.app.Activity
import android.content.Context
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
import io.flutter.plugin.common.MethodChannel

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
        stopRanging { }
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
    
    // This is the function that will be called from Dart to request permissions
    override fun requestPermissions(callback: (Result<Boolean>) -> Unit) {
        val act = activity
        if (act == null) {
            callback(Result.failure(IllegalStateException("Plugin not attached to an activity.").toFlutterError()))
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val permission = Manifest.permission.UWB_RANGING
            if (ContextCompat.checkSelfPermission(act, permission) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(act, arrayOf(permission), requestCode)
                // We can't know the result immediately, so we return false.
                // The app should re-query the permission status or re-trigger the action
                // after the user has responded to the dialog.
                callback(Result.success(false))
            } else {
                callback(Result.success(true))
            }
        } else {
            // UWB not supported on older versions, so permission is not applicable.
            callback(Result.success(false))
        }
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

    override fun startRanging(
        peerAddress: ByteArray,
        config: UwbSessionConfig,
        callback: (Result<Unit>) -> Unit
    ) {
        val scope = controllerSessionScope
        if (scope == null) {
            val error =
                IllegalStateException("UWB session not initialized. Call getLocalUwbAddress first.")
            Log.e(logTag, "Ranging failed", error)
            callback(Result.failure(error.toFlutterError()))
            return
        }

        try {
            val rangingParameters = RangingParameters(
                uwbConfigType = RangingParameters.CONFIG_UNICAST_DS_TWR,
                sessionId = config.sessionId.toInt(),
                sessionKeyInfo = config.sessionKeyInfo,
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

            callback(Result.success(Unit))
        } catch (e: Exception) {
            Log.e(logTag, "Failed to start ranging", e)
            callback(Result.failure(e.toFlutterError()))
        }
    }

    private fun handleRangingResult(rangingResult: RangingResult, peerAddressBytes: ByteArray) {
        val device = UwbDevice(address = peerAddressBytes)
        when (rangingResult) {
            is RangingResult.RangingResultPosition -> {
                val position = rangingResult.position
                val data = UwbRangingData(
                    distance = position.distance?.value?.toDouble() ?: 0.0,
                    azimuth = position.azimuth?.value?.toDouble() ?: 0.0,
                    elevation = position.elevation?.value?.toDouble() ?: 0.0,
                )
                flutterApi.onRangingResult(device, data) {}
            }
            is RangingResult.RangingResultPeerDisconnected -> {
                flutterApi.onPeerDisconnected(device) {}
            }
        }
    }

    override fun stopRanging(callback: (Result<Unit>) -> Unit) {
        rangingJob?.dispose()
        rangingJob = null
        callback(Result.success(Unit))
    }
}

private fun Throwable.toFlutterError(): FlutterError {
    return FlutterError("NATIVE_ERROR", this.message, this.stackTraceToString())
}
