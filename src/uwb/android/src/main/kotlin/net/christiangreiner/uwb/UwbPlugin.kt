package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbManager
import androidx.core.uwb.UwbClientSessionScope
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import java.util.UUID

// Import the generated Pigeon classes
import net.christiangreiner.uwb.RangingResult as PigeonRangingResult

class UwbPlugin : FlutterPlugin, UwbHostApi {

    private var appContext: Context? = null
    private var flutterApi: UwbFlutterApi? = null
    private val scope = CoroutineScope(Dispatchers.Main)
    
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
        uwbManager = UwbManager.createInstance(context)
        callback(Result.success(Unit))
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
                clientSessionScope = manager.accessorySessionScope()
                val configData = clientSessionScope!!.localAddress.address
                callback(Result.success(configData))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun initializeAndroidController(accessoryConfigurationData: ByteArray, callback: (Result<ByteArray>) -> Unit) {
        val manager = uwbManager ?: return callback(Result.failure(Exception("UwbManager not initialized")))
        scope.launch {
            try {
                clientSessionScope = manager.controllerSessionScope()
                // The ranging parameters need to be prepared before getting the shareable data.
                // This will be handled in startAndroidRanging.
                callback(Result.success(clientSessionScope!!.localAddress.address))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun startAndroidRanging(configData: ByteArray, isController: Boolean, callback: (Result<Unit>) -> Unit) {
        val sessionScope = clientSessionScope ?: return callback(Result.failure(Exception("UwbClientSessionScope not initialized")))
        rangingJob?.cancel()
        
        scope.launch {
            try {
                val sessionFlow = sessionScope.prepareSession(configData)
                rangingJob = sessionScope.rangingResultsFlow().onEach {
                    when (it) {
                        is RangingResult.RangingResultPosition -> {
                            val position = it.position
                            val result = PigeonRangingResult(
                                peerAddress = position.uwbDevice.address.toString(),
                                deviceName = "",
                                distance = position.distance.value.toDouble(),
                                azimuth = position.azimuth?.value?.toDouble(),
                                elevation = position.elevation?.value?.toDouble()
                            )
                            flutterApi?.onRangingResult(result) {}
                        }
                        is RangingResult.RangingResultPeerDisconnected -> {
                            // Handle peer disconnection
                        }
                    }
                }.launchIn(scope)
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
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
