package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbClient
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

class UwbPlugin : FlutterPlugin, UwbHostApi {

    private var appContext: Context? = null
    private var flutterApi: UwbFlutterApi? = null
    private val scope = CoroutineScope(Dispatchers.Main)
    
    // UWB-specific properties, moved from UwbConnectionManager
    private var uwbClient: UwbClient? = null
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
        callback(Result.success(Unit))
    }

    override fun stop(callback: (Result<Unit>) -> Unit) {
        rangingJob?.cancel()
        rangingJob = null
        uwbClient = null
        callback(Result.success(Unit))
    }

    override fun getAndroidAccessoryConfigurationData(callback: (Result<ByteArray>) -> Unit) {
        val context = appContext ?: return callback(Result.failure(Exception("AppContext is null")))
        scope.launch {
            try {
                val client = UwbClient.getAccessoryClient(context)
                uwbClient = client
                callback(Result.success(client.localAddress.address))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun initializeAndroidController(accessoryConfigurationData: ByteArray, callback: (Result<ByteArray>) -> Unit) {
        val context = appContext ?: return callback(Result.failure(Exception("AppContext is null")))
        scope.launch {
            try {
                val client = UwbClient.getControllingClient(context)
                uwbClient = client
                val rangingParameters = client.prepareSession(accessoryConfigurationData)
                callback(Result.success(rangingParameters.shareableData))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun startAndroidRanging(configData: ByteArray, isController: Boolean, callback: (Result<Unit>) -> Unit) {
        val context = appContext ?: return callback(Result.failure(Exception("AppContext is null")))
        scope.launch {
            try {
                if (!isController) {
                    uwbClient = UwbClient.getAccessoryClient(context)
                }

                val client = uwbClient ?: return@launch callback(Result.failure(Exception("UwbClient not initialized")))

                if (rangingJob?.isActive == true) {
                    rangingJob?.cancel()
                }

                val sessionFlow = if (isController) {
                    client.controllerRanging(configData)
                } else {
                    client.accessoryRanging(configData)
                }

                rangingJob = sessionFlow.onEach {
                    when (it) {
                        is RangingResult.RangingResultPosition -> {
                            val position = it.position
                            val result = RangingResult(
                                peerAddress = position.device.address.toString(),
                                deviceName = "",
                                distance = position.position.distance?.value?.toDouble(),
                                azimuth = position.position.azimuth?.value?.toDouble(),
                                elevation = position.position.elevation?.value?.toDouble()
                            )
                            flutterApi?.onRangingResult(result) {}
                        }
                        is RangingResult.RangingResultLoss -> {
                            // Handled by BLE layer
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
