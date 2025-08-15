package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.RangingParameters
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbAddress
import androidx.core.uwb.UwbClientSessionScope
import androidx.core.uwb.UwbManager
import androidx.core.uwb.UwbDevice
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
        clientSessionScope = null
        uwbManager = null
        callback(Result.success(Unit))
    }

    override fun getAndroidAccessoryConfigurationData(callback: (Result<ByteArray>) -> Unit) {
        val manager = uwbManager ?: return callback(Result.failure(Exception("UwbManager not initialized")))
        scope.launch {
            try {
                // This is the correct way to set up the device as an "Accessory" or "Controlee"
                val sessionScope = manager.controleeSessionScope()
                clientSessionScope = sessionScope
                callback(Result.success(sessionScope.localAddress.address))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun initializeAndroidController(accessoryConfigurationData: ByteArray, sessionKeyInfo: ByteArray, sessionId: Long, callback: (Result<ByteArray>) -> Unit) {
        val manager = uwbManager ?: return callback(Result.failure(Exception("UwbManager not initialized")))
        scope.launch {
            try {
                // This is the correct way to set up the device as a "Controller"
                val sessionScope = manager.controllerSessionScope()
                clientSessionScope = sessionScope
                
                val accessoryAddress = UwbAddress(accessoryConfigurationData)
                val rangingParameters = RangingParameters(
                    uwbConfigType = RangingParameters.UWB_CONFIG_ID_1,
                    sessionId = sessionId.toInt(),
                    sessionKeyInfo = sessionKeyInfo,
                    complexChannel = null,
                    peerDevices = listOf(UwbDevice.createForAddress(accessoryAddress)),
                    updateRateType = RangingParameters.RANGING_UPDATE_RATE_AUTOMATIC
                )

                // Start the session and listen for results.
                val sessionFlow = sessionScope.prepareSession(rangingParameters)
                rangingJob?.cancel()
                rangingJob = sessionFlow.onEach {
                    handleRangingResult(it)
                }.launchIn(scope)
                
                // Return the local address of this controller to be sent back to the accessory.
                callback(Result.success(sessionScope.localAddress.address))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun startAndroidRanging(configData: ByteArray, isController: Boolean, sessionKeyInfo: ByteArray, sessionId: Long, callback: (Result<Unit>) -> Unit) {
        val sessionScope = clientSessionScope ?: return callback(Result.failure(Exception("UwbClientSessionScope not initialized")))
        scope.launch {
            try {
                val peerAddress = UwbAddress(configData)
                val rangingParameters = RangingParameters(
                    uwbConfigType = RangingParameters.UWB_CONFIG_ID_1,
                    sessionId = sessionId.toInt(),
                    sessionKeyInfo = sessionKeyInfo,
                    complexChannel = null,
                    peerDevices = listOf(UwbDevice.createForAddress(peerAddress)),
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
                val position = result.position
                val pigeonResult = PigeonRangingResult(
                    // Correctly access the uwbDevice property
                    peerAddress = position.device.address.toString(),
                    deviceName = "", // Device name is not available in the ranging result
                    // Correctly handle nullable RangingMeasurement values
                    distance = position.distance?.value?.toDouble(),
                    azimuth = position.azimuth?.value?.toDouble(),
                    elevation = position.elevation?.value?.toDouble()
                )
                flutterApi?.onRangingResult(pigeonResult) {}
            }
            is RangingResult.RangingResultPeerDisconnected -> {
                // You can notify Flutter about the disconnection here if needed
            }
        }
    }

    override fun startIosController(callback: (Result<ByteArray>) -> Unit) {
        callback(Result.failure(Exception("This method is for iOS only.")))
    }

    override fun startIosAccessory(token: ByteArray, callback: (Result<Unit>) -> Unit) {
        callback(Result.failure(Exception("This method is for iOS only.")))
    }
}
