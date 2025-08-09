package net.christiangreiner.uwb

import android.content.Context
import android.util.Log
import androidx.core.uwb.RangingParameters
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbAddress
import androidx.core.uwb.UwbComplexChannel
import androidx.core.uwb.UwbControllerSessionScope
import androidx.core.uwb.UwbManager
import androidx.core.uwb.rxjava3.controllerSessionScopeSingle
import androidx.core.uwb.rxjava3.rangingResultsFlowable
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.reactivex.rxjava3.disposables.Disposable

class UwbPlugin : FlutterPlugin, UwbHostApi {
    private val logTag = "UwbPlugin"

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
        // Do not close the scope here, it can be reused.
        // It will be closed when the plugin is detached.
        callback(Result.success(Unit))
    }
}

private fun Throwable.toFlutterError(): FlutterError {
    return FlutterError("NATIVE_ERROR", this.message, this.stackTraceToString())
}
