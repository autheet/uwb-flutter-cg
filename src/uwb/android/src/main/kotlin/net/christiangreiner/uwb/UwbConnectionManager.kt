package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.UwbManager
import androidx.core.uwb.UwbDevice as PlatformUwbDevice
import androidx.core.uwb.RangingParameters
import androidx.core.uwb.RangingSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

class UwbConnectionManager(
    private val context: Context,
    private val onDeviceRanged: (UwbDevice) -> Unit,
    private val onSessionError: (String) -> Unit,
    private val onSessionStarted: (UwbDevice) -> Unit,
) {

    private var uwbManager: UwbManager? = null
    private val coroutineScope = CoroutineScope(Dispatchers.Main + Job())
    private var rangingSession: RangingSession? = null

    init {
        uwbManager = UwbManager.createInstance(context)
    }

    fun startControllerSession(config: UwbConfig) {
        val uwbClient = uwbManager?.getControllingClient(context)
        // In controller mode, we don't need a peer address to start the session.
        // The accessory will advertise and the controller will find it.
        val rangingParameters = RangingParameters(
            uwbConfigType = RangingParameters.CONFIG_UNICAST_DS_TWR,
            sessionId = config.sessionId.toInt(),
            sessionKeyInfo = config.sessionKeyInfo,
            subSessionId = null,
            subSessionKeyInfo = null,
            complexChannel = null,
            peerDevices = emptyList(), // No peer needed to start as a controller
            updateRateType = RangingParameters.RANGING_UPDATE_RATE_AUTOMATIC
        )

        coroutineScope.launch {
            uwbClient?.let { client ->
                val session = client.startRanging(rangingParameters)
                rangingSession = session
                // onSessionStarted will be called when an accessory is found
                session
                    .onEach { rangingResult ->
                        val pigeonDevice = UwbDataHandler.rangingResultToPigeon(rangingResult)
                        onDeviceRanged(pigeonDevice)
                    }
                    .catch { e -> onSessionError(e.toString()) }
                    .launchIn(this)
            }
        }
    }

    fun startAccessorySession(config: UwbConfig) {
        val uwbClient = uwbManager?.getAccessoryClient(context)
         val rangingParameters = RangingParameters(
            uwbConfigType = RangingParameters.CONFIG_UNICAST_DS_TWR,
            sessionId = config.sessionId.toInt(),
            sessionKeyInfo = config.sessionKeyInfo,
            subSessionId = null,
            subSessionKeyInfo = null,
            complexChannel = null,
            peerDevices = emptyList(), // No peer needed to start as an accessory
            updateRateType = RangingParameters.RANGING_UPDATE_RATE_AUTOMATIC
        )
        coroutineScope.launch {
            uwbClient?.let { client ->
                val session = client.startRanging(rangingParameters)
                rangingSession = session
                // onSessionStarted will be called when a controller starts ranging with us
                session
                    .onEach { rangingResult ->
                        val pigeonDevice = UwbDataHandler.rangingResultToPigeon(rangingResult)
                        onDeviceRanged(pigeonDevice)
                    }
                    .catch { e -> onSessionError(e.toString()) }
                    .launchIn(this)
            }
        }
    }

    fun stopRanging(peerAddress: String) {
        stopAllSessions()
    }

    fun stopAllSessions() {
        rangingSession?.close()
        rangingSession = null
        uwbManager = null
    }

    fun getLocalAddress(): ByteArray? {
        return uwbManager?.adapterState?.value?.localAddress?.address
    }

    fun isUwbSupported(): Boolean {
        return uwbManager != null
    }
}
