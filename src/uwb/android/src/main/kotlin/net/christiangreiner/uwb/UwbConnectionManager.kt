package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.RangingParameters
import androidx.core.uwb.UwbManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbDevice as UwbPeerDevice // Alias to avoid name clash

// Import Pigeon-generated classes
import net.christiangreiner.uwb.UwbDevice
import net.christiangreiner.uwb.UwbSessionConfig
import net.christiangreiner.uwb.UwbData
import net.christiangreiner.uwb.Direction3D
import net.christiangreiner.uwb.DeviceType
import net.christiangreiner.uwb.DeviceState

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

    fun getLocalAddress() = uwbManager.localAddress

    fun startRanging(rangingParameters: RangingParameters, config: UwbSessionConfig) {
        rangingScope = CoroutineScope(appCoroutineScope.coroutineContext)
        rangingScope?.launch {
            try {
                uwbManager.rangingSessions(rangingParameters).collect { rangingResult ->
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
                    id = config.sessionId.toString(), // Use session ID as a unique identifier
                    name = "", // Name is handled at a higher level
                    deviceType = DeviceType.accessory,
                    state = DeviceState.ranging,
                    uwbData = UwbData(
                        distance = position.distance?.value?.toDouble(),
                        azimuth = position.azimuth?.value?.toDouble(),
                        elevation = position.elevation?.value?.toDouble(),
                        direction = null // Android does not provide a 3D direction vector
                    )
                )
                listener.onRangingResult(device)
            }
            is RangingResult.RangingResultPeerDisconnected -> {
                val device = UwbDevice(
                    id = config.sessionId.toString(),
                    name = "",
                    deviceType = DeviceType.accessory,
                    state = DeviceState.disconnected
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
