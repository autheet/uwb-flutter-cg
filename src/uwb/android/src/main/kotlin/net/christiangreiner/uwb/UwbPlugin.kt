package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.UwbClient
import io.flutter.embedding.engine.plugins.FlutterPlugin

class UwbPlugin : FlutterPlugin, UwbHostApi {

    private var appContext: Context? = null
    private var uwbClient: UwbClient? = null
    private var uwbConnectionManager: UwbConnectionManager? = null
    private var flutterApi: UwbFlutterApi? = null

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

    private fun getManager(uwbClient: UwbClient): UwbConnectionManager {
        if (uwbConnectionManager == null) {
            uwbConnectionManager = UwbConnectionManager(
                uwbClient,
                onRangingResult = { device ->
                    flutterApi?.onRangingResult(device) {}
                },
                onRangingError = { error ->
                    flutterApi?.onRangingError(error) {}
                }
            )
        }
        return uwbConnectionManager!!
    }

    override fun isSupported(result: (Result<Boolean>) -> Unit) {
        result(Result.success(appContext != null && UwbClient.isUwbSupported(appContext!!)))
    }

    override fun getLocalEndpoint(result: (Result<ByteArray>) -> Unit) {
        if (appContext == null) {
            result(Result.failure(Exception("App context not available.")))
            return
        }
        // Always create a new client for the local endpoint, as the session may not have started yet.
        val client = UwbClient.getControllingClient(appContext!!)
        result(Result.success(client.localAddress))
    }

    override fun startRanging(peerEndpoint: ByteArray, isController: Boolean, result: (Result<Unit>) -> Unit) {
        if (appContext == null) {
            result(Result.failure(Exception("App context not available.")))
            return
        }
        uwbClient = if (isController) {
            UwbClient.getControllingClient(appContext!!)
        } else {
            UwbClient.getAccessoryClient(appContext!!)
        }
        getManager(uwbClient!!).startRanging(peerEndpoint)
        result(Result.success(Unit))
    }

    override fun stopRanging(result: (Result<Unit>) -> Unit) {
        if (uwbConnectionManager == null) {
            result(Result.failure(Exception("Ranging not started.")))
            return
        }
        uwbConnectionManager!!.stopRanging()
        result(Result.success(Unit))
    }

    override fun closeSession(result: (Result<Unit>) -> Unit) {
        if (uwbConnectionManager != null) {
            uwbConnectionManager!!.closeSession()
            uwbConnectionManager = null
        }
        uwbClient = null
        result(Result.success(Unit))
    }
}
