package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.UwbClient
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class UwbPlugin : FlutterPlugin, UwbHostApi {

    private var appContext: Context? = null
    private var uwbConnectionManager: UwbConnectionManager? = null
    private var flutterApi: UwbFlutterApi? = null
    private val scope = CoroutineScope(Dispatchers.Main)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        UwbHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = UwbFlutterApi(binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, null)
        appContext = null
        flutterApi = null
    }

    private fun getRangingManager(client: UwbClient): UwbConnectionManager {
        return UwbConnectionManager(
            uwbClient = client,
            onRangingResult = { result ->
                flutterApi?.onRangingResult(result) {}
            },
            onRangingError = { error ->
                flutterApi?.onRangingError(error) {}
            }
        )
    }
    
    override fun start(deviceName: String, serviceUUIDDigest: String, callback: (Result<Unit>) -> Unit) {
        callback(Result.success(Unit))
    }

    override fun stop(callback: (Result<Unit>) -> Unit) {
        scope.launch {
            try {
                uwbConnectionManager?.stopRanging()
                uwbConnectionManager = null
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getAndroidAccessoryConfigurationData(callback: (Result<ByteArray>) -> Unit) {
        val context = appContext ?: return callback(Result.failure(Exception("AppContext is null")))
        scope.launch {
            try {
                val client = UwbClient.getAccessoryClient(context)
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
                uwbConnectionManager = getRangingManager(client)
                val shareableData = uwbConnectionManager!!.prepareControllerSession(accessoryConfigurationData)
                callback(Result.success(shareableData))
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
                    val client = UwbClient.getAccessoryClient(context)
                    uwbConnectionManager = getRangingManager(client)
                }
                uwbConnectionManager?.startRanging(configData, isController)
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
