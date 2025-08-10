package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.RangingParameters
import androidx.core.uwb.UwbManager
import androidx.core.uwb.UwbClient
import androidx.core.uwb.RangingResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import java.lang.Exception

// Listener interface to decouple from Flutter
interface UwbConnectionListener {
    fun onRangingResult(device: UwbDevice)
    fun onRangingError(error: Exception)
    fun onPeerDisconnected(device: UwbDevice)
}

class UwbConnectionManager(
    private val context: Context,
    private val uwbManager: UwbManager,
    private val listener: UwbConnectionListener,
    private val appCoroutineScope: CoroutineScope
) {
    private var rangingScope: CoroutineScope? = null
    private val uwbClient: UwbClient by lazy { uwbManager.createClient(context) }

    fun getLocalAddress() = uwbClient.localAddress

    fun startRanging(rangingParameters: RangingParameters, config: UwbSessionConfig) {
        rangingScope = CoroutineScope(appCoroutineScope.coroutineContext)
        rangingScope?.launch {
            try {
                uwbClient.rangingSessions(rangingParameters).collect { rangingResult ->
                    handleRangingResult(rangingResult, config)
                }
            } catch (e: Exception) {
                listener.onRangingError(e)
            }
        }
    }

    private fun handleRangingResult(rangingResult: RangingResult, config: UwbSessionConfig) {
        when (rangingResult) {
            is RangingResult.RangingResultPosition -> {
                val position = rangingResult.position
                val device = UwbDevice(
                    id = config.sessionId.toString(),
                    name = "",
                    deviceType = DeviceType.ACCESSORY,
                    state = DeviceState.RANGING,
                    uwbData = UwbData(
                        distance = position.distance?.value?.toDouble(),
                        azimuth = position.azimuth?.value?.toDouble(),
                        elevation = position.elevation?.value?.toDouble(),
                        direction = null
                    )
                )
                listener.onRangingResult(device)
            }
            is RangingResult.RangingResultPeerDisconnected -> {
                val device = UwbDevice(
                    id = config.sessionId.toString(),
                    name = "",
                    deviceType = DeviceType.ACCESSORY,
                    state = DeviceState.DISCONNECTED
                )
                listener.onPeerDisconnected(device)
            }
        }
    }

    fun stopRanging() {
        rangingScope?.cancel()
        rangingScope = null
    }
}
