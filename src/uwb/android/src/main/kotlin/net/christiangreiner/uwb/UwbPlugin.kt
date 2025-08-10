package net.christiangreiner.uwb

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin

class UwbPlugin : FlutterPlugin, UwbHostApi {

    private var appContext: Context? = null
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

    private fun getManager(): UwbConnectionManager {
        if (uwbConnectionManager == null) {
            uwbConnectionManager = UwbConnectionManager(
                appContext!!,
                onDeviceRanged = { device ->
                    flutterApi?.onRanging(device) {}
                },
                onSessionError = { error ->
                    // Handle error, maybe send to Flutter
                },
                onSessionStarted = { device ->
                    flutterApi?.onUwbSessionStarted(device) {}
                }
            )
        }
        return uwbConnectionManager!!
    }

    override fun getLocalUwbAddress(result: UwbHostApi.Result<ByteArray>?) {
        val address = getManager().getLocalAddress()
        if (address != null) {
            result?.success(address)
        } else {
            result?.error(Exception("UWB address not available"))
        }
    }

    override fun isUwbSupported(result: UwbHostApi.Result<Boolean>?) {
        result?.success(getManager().isUwbSupported())
    }

    override fun startControllerSession(config: UwbConfig) {
        getManager().startControllerSession(config)
    }

    override fun startAccessorySession(config: UwbConfig) {
        getManager().startAccessorySession(config)
    }
    
    override fun startPeerSession(peerToken: ByteArray, config: UwbConfig) {
        // Not implemented on Android, this is an iOS-specific method.
        // Android uses the controller/accessory model.
    }

    override fun stopRanging(peerAddress: String) {
        getManager().stopRanging(peerAddress)
    }

    override fun stopUwbSessions() {
        getManager().stopAllSessions()
        uwbConnectionManager = null
    }
}
