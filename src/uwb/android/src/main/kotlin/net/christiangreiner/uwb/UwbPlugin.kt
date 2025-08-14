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
            context = appContext!!,
            uwbClient = client,
            onRangingResult = { result ->
                flutterApi?.onRangingResult(result) {}
            },
            onRangingError = { error ->
                flutterApi?.onRangingError(error) {}
            }
        )
    }
    
    // --- PEER-TO-PEER (UNSUPPORTED ON ANDROID) ---

    override fun getPeerDiscoveryToken(callback: (Result<ByteArray>) -> Unit) {
        callback(Result.failure(Exception("Peer-to-peer ranging is not supported on Android.")))
    }

    override fun startPeerRanging(token: ByteArray, callback: (Result<Unit>) -> Unit) {
        callback(Result.failure(Exception("Peer-to-peer ranging is not supported on Android.")))
    }

    // --- ACCESSORY RANGING (SUPPORTED) ---

    override fun getAccessoryConfigurationData(callback: (Result<ByteArray>) -> Unit) {
        val context = appContext ?: return callback(Result.failure(Exception("AppContext is null")))
        scope.launch {
            try {
                // This device is acting as an accessory.
                val client = UwbClient.getAccessoryClient(context)
                // The config data is its local address.
                callback(Result.success(client.localAddress.address))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun startControllerRanging(accessoryData: ByteArray, callback: (Result<ByteArray>) -> Unit) {
        val context = appContext ?: return callback(Result.failure(Exception("AppContext is null")))
        scope.launch {
            try {
                // This device is acting as the controller.
                val client = UwbClient.getControllingClient(context)
                uwbConnectionManager = getRangingManager(client)
                // Prepare the session with the accessory's data and get the shareable config data.
                val shareableData = uwbConnectionManager!!.prepareControllerSession(accessoryData)
                // Return the shareable data to be sent back to the accessory.
                callback(Result.success(shareableData))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun startAccessoryRanging(shareableData: ByteArray, callback: (Result<Unit>) -> Unit) {
        val context = appContext ?: return callback(Result.failure(Exception("AppContext is null")))
        scope.launch {
            try {
                // This device is acting as an accessory. It needs its own client.
                val client = UwbClient.getAccessoryClient(context)
                uwbConnectionManager = getRangingManager(client)
                // Start ranging using the controller's shareable data.
                uwbConnectionManager!!.startRanging(shareableData, false)
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun stopRanging(callback: (Result<Unit>) -> Unit) {
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
}
