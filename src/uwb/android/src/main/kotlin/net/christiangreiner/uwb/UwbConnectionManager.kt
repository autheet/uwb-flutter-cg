package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.UwbClient
import androidx.core.uwb.UwbDevice
import androidx.core.uwb.UwbAddress
import androidx.core.uwb.RangingParameters
import androidx.core.uwb.RangingSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.cancel
import net.christiangreiner.uwb.UwbSessionConfig as PigeonUwbConfig
import net.christiangreiner.uwb.UwbDevice as PigeonUwbDevice
import net.christiangreiner.uwb.DeviceType
import net.christiangreiner.uwb.DeviceState
import net.christiangreiner.uwb.UwbData
import net.christiangreiner.uwb.Direction3D
import java.util.concurrent.ConcurrentHashMap

class UwbConnectionManager(
    private val context: Context,
    val onRanging: (device: PigeonUwbDevice) -> Unit,
    val onDisconnected: (device: PigeonUwbDevice) -> Unit
) {
    private val uwbClient: UwbClient by lazy {
        UwbClient.createClient(context)
    }
    private val coroutineScope = CoroutineScope(Dispatchers.Main + Job())
    private val rangingSessions = ConcurrentHashMap<String, RangingSession>()

    fun getLocalAddress(): ByteArray {
        return uwbClient.localAddress.address
    }

    fun startRanging(peerAddress: ByteArray, uwbConfig: PigeonUwbConfig) {
        val peerUwbAddress = UwbAddress(peerAddress)
        val rangingParams = RangingParameters(
            uwbConfig.toRangingConfig(),
            listOf(UwbDevice(peerUwbAddress))
        )

        val session = uwbClient.rangingSessions(rangingParams)
        session.onEach {
            val pigeonDevice = it.device.toPigeonDevice(it.rangingResult)
            onRanging(pigeonDevice)
        }.launchIn(coroutineScope)

        rangingSessions[peerAddress.toString()] = session
    }

    fun stopRanging(peerAddress: String) {
        rangingSessions[peerAddress]?.close()
        rangingSessions.remove(peerAddress)
    }

    fun stopAllRanging() {
        rangingSessions.values.forEach { it.close() }
        rangingSessions.clear()
        coroutineScope.cancel()
    }

    private fun PigeonUwbConfig.toRangingConfig(): RangingParameters.UwbConfig {
        return RangingParameters.UwbConfig(
            sessionId,
            sessionKeyInfo,
            RangingParameters.UwbConfig.ComplexChannel(channel.toInt(), preambleIndex.toInt()),
            listOf(), // Add any additional parameters here.
            RangingParameters.CONFIG_UNICAST_DS_TWR
        )
    }

    private fun UwbDevice.toPigeonDevice(rangingResult: RangingSession.RangingResult): PigeonUwbDevice {
        val (distance, azimuth, elevation) = when (rangingResult) {
            is RangingSession.RangingResult.RangingResultPosition -> Triple(
                rangingResult.position.distance,
                rangingResult.position.azimuth,
                rangingResult.position.elevation
            )
            is RangingSession.RangingResult.RangingResultUnsuccessful -> Triple(null, null, null)
        }

        return PigeonUwbDevice(
            id = this.address.toString(),
            name = "Unknown", // You may need a way to resolve the device name.
            uwbData = UwbData(
                distance = distance?.value,
                azimuth = azimuth?.value,
                elevation = elevation?.value,
                direction = null,
                horizontalAngle = null
            ),
            deviceType = DeviceType.SMARTPHONE, // This may need to be determined.
            state = DeviceState.RANGING
        )
    }
}
