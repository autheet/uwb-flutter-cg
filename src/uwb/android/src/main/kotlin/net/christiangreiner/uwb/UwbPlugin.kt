package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.RangingParameters
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbAddress
import androidx.core.uwb.UwbClientSessionScope
import androidx.core.uwb.UwbManager
import androidx.core.uwb.UwbDevice
import androidx.core.uwb.UwbComplexChannel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

// Import the generated Pigeon classes
import net.christiangreiner.uwb.RangingResult as PigeonRangingResult
import net.christiangreiner.uwb.UwbConfig as PigeonUwbConfig

class UwbPlugin : FlutterPlugin, UwbHostApi {

    private var appContext: Context? = null
    private var flutterApi: UwbFlutterApi? = null
    private val scope = CoroutineScope(Dispatchers.Main + Job())
    
    private var uwbManager: UwbManager? = null
    private var clientSessionScope: UwbClientSessionScope? = null
    private var rangingJob: Job? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        UwbHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = UwbFlutterApi(binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, null)
        appContext = null
        flutterApi = null
        scope.cancel()
    }
    
    // --- Session Management ---
    override fun start(deviceName: String, serviceUUIDDigest: String, callback: (Result<Unit>) -> Unit) {
        val context = appContext ?: return callback(Result.failure(Exception("AppContext is null")))
        scope.launch {
            try {
                uwbManager = UwbManager.createInstance(context)
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun stop(callback: (Result<Unit>) -> Unit) {
        rangingJob?.cancel()
        rangingJob = null
        clientSessionScope?.cancel()
        clientSessionScope = null
        uwbManager = null
        callback(Result.success(Unit))
    }

    // --- FiRa Accessory Ranging (Android Implementation) ---

    // Step 1: An accessory gets its own UWB address to share with a controller.
    override fun getAccessoryAddress(callback: (Result<ByteArray>) -> Unit) {
        val manager = uwbManager ?: return callback(Result.failure(Exception("UwbManager not initialized")))
        scope.launch {
            try {
                // For the accessory (controlee) role, we establish the session scope.
                // The localAddress from this scope is the data sent to the controller.
                clientSessionScope?.cancel() // Ensure any old session is closed.
                val sessionScope = manager.controleeSessionScope()
                clientSessionScope = sessionScope
                callback(Result.success(sessionScope.localAddress.address))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    // Step 2: A controller takes an accessory's address and generates the full config for the session.
    override fun generateControllerConfig(accessoryAddress: ByteArray, sessionKeyInfo: ByteArray, sessionId: Long, callback: (Result<PigeonUwbConfig>) -> Unit) {
        val manager = uwbManager ?: return callback(Result.failure(Exception("UwbManager not initialized")))
        scope.launch {
            try {
                clientSessionScope?.cancel() // Ensure any old session is closed.
                val sessionScope = manager.controllerSessionScope()
                clientSessionScope = sessionScope

                val peerAddress = UwbAddress(accessoryAddress)
                // Use standard FiRa-compliant settings. Channel 9 is the most common.
                val configId = RangingParameters.CONFIG_UNICAST_DS_TWR
                val channel = 9
                val preamble = 10 
                val complexChannel = UwbComplexChannel(channel, preamble)

                val rangingParameters = RangingParameters(
                    uwbConfigType = configId,
                    sessionId = sessionId.toInt(),
                    subSessionId = 0,
                    sessionKeyInfo = sessionKeyInfo,
                    subSessionKeyInfo = null,
                    complexChannel = complexChannel,
                    peerDevices = listOf(UwbDevice.createForAddress(peerAddress.address)),
                    updateRateType = RangingParameters.RANGING_UPDATE_RATE_AUTOMATIC
                )

                rangingJob?.cancel()
                rangingJob = sessionScope.prepareSession(rangingParameters).onEach { handleRangingResult(it) }.launchIn(scope)
                
                // Return the full config object so the other device knows exactly what parameters to use.
                val config = PigeonUwbConfig(
                    uwbConfigId = configId.toLong(),
                    sessionId = sessionId,
                    sessionKeyInfo = sessionKeyInfo,
                    channel = channel.toLong(),
                    preambleIndex = preamble.toLong(),
                    peerAddress = sessionScope.localAddress.address
                )
                callback(Result.success(config))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    // Step 3: An accessory receives the full config from the controller and starts ranging.
    override fun startAccessoryRanging(config: PigeonUwbConfig, callback: (Result<Unit>) -> Unit) {
        val sessionScope = clientSessionScope ?: return callback(Result.failure(Exception("UwbClientSessionScope not initialized. Was getAccessoryAddress called?")))
        
        scope.launch {
            try {
                // This is the critical change. We now use the exact parameters from the controller.
                val controllerAddress = UwbAddress(config.peerAddress)
                val complexChannel = UwbComplexChannel(config.channel.toInt(), config.preambleIndex.toInt())

                val rangingParameters = RangingParameters(
                    uwbConfigType = config.uwbConfigId.toInt(),
                    sessionId = config.sessionId.toInt(),
                    subSessionId = 0,
                    sessionKeyInfo = config.sessionKeyInfo,
                    subSessionKeyInfo = null,
                    complexChannel = complexChannel,
                    peerDevices = listOf(UwbDevice.createForAddress(controllerAddress.address)),
                    updateRateType = RangingParameters.RANGING_UPDATE_RATE_AUTOMATIC
                )

                rangingJob?.cancel()
                rangingJob = sessionScope.prepareSession(rangingParameters).onEach {
                    handleRangingResult(it)
                }.launchIn(scope)

                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }
    
    private fun handleRangingResult(result: RangingResult) {
        when (result) {
            is RangingResult.RangingResultPosition -> {
                val pigeonResult = PigeonRangingResult(
                    peerAddress = result.device.address.toString(),
                    deviceName = "", // Device name is handled by the Dart layer
                    distance = result.position.distance?.value?.toDouble(),
                    azimuth = result.position.azimuth?.value?.toDouble(),
                    elevation = result.position.elevation?.value?.toDouble()
                )
                flutterApi?.onRangingResult(pigeonResult) {}
            }
            is RangingResult.RangingResultPeerDisconnected -> {
                flutterApi?.onPeerLost("", result.device.address.toString()) {}
            }
        }
    }

    // --- iOS Peer-to-Peer Ranging (Not used on Android) ---
    override fun startIosController(callback: (Result<ByteArray>) -> Unit) {
        callback(Result.failure(Exception("This method is for iOS only.")))
    }

    override fun startIosAccessory(token: ByteArray, callback: (Result<Unit>) -> Unit) {
        callback(Result.failure(Exception("This method is for iOS only.")))
    }
}
