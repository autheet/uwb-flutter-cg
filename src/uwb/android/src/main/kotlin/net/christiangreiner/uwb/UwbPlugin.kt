package net.christiangreiner.uwb

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
import java.util.HashMap

private fun Throwable.toFlutterError(): FlutterError {
    return FlutterError("NATIVE_ERROR", this.message, this.stackTraceToString())
}

class UwbPlugin : FlutterPlugin, UwbHostApi {
    private lateinit var uwbManager: UwbManager
    private lateinit var flutterApi: UwbFlutterApi

    private var controllerSessionScope: UwbControllerSessionScope? = null
    private val rangingJobs = HashMap<String, Disposable>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = UwbFlutterApi(binding.binaryMessenger)
        uwbManager = UwbManager.createInstance(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, null)
        stopUwbSessions()
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
            callback(Result.failure(error.toFlutterError()))
        })
    }

    override fun startRanging(peerAddress: ByteArray, config: UwbSessionConfig, isAccessory: Boolean) {
        val scope = controllerSessionScope ?: return

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

            val peerAddressString = peerAddress.contentToString()
            rangingJobs[peerAddressString]?.dispose() // Dispose of any existing job for this peer
            val job = scope.rangingResultsFlowable(rangingParameters)
                .subscribe({ rangingResult ->
                    handleRangingResult(rangingResult, peerAddress)
                }, { error ->
                    flutterApi.onRangingError(error.toFlutterError()) {}
                })
            rangingJobs[peerAddressString] = job
        } catch (e: Exception) {
            flutterApi.onRangingError(e.toFlutterError()) {}
        }
    }

    private fun handleRangingResult(rangingResult: RangingResult, peerAddressBytes: ByteArray) {
        // The name is discovered and managed in the Dart layer.
        val device = UwbDevice(address = peerAddressBytes, name = "", rangingData = null)
        when (rangingResult) {
            is RangingResult.RangingResultPosition -> {
                val position = rangingResult.position
                val data = UwbRangingData(
                    distance = position.distance?.value?.toDouble(),
                    azimuth = position.azimuth?.value?.toDouble(),
                    elevation = position.elevation?.value?.toDouble()
                )
                val resultWithData = UwbDevice(address = device.address, name = device.name, rangingData = data)
                flutterApi.onRangingResult(resultWithData) {}
            }
            is RangingResult.RangingResultPeerDisconnected -> {
                flutterApi.onPeerDisconnected(device) {}
            }
        }
    }

    override fun stopRanging(peerAddress: ByteArray) {
        val peerAddressString = peerAddress.contentToString()
        rangingJobs[peerAddressString]?.dispose()
        rangingJobs.remove(peerAddressString)
    }

    override fun stopUwbSessions() {
        rangingJobs.values.forEach { it.dispose() }
        rangingJobs.clear()
    }
}
