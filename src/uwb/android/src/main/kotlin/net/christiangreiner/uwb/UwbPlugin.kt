package net.christiangreiner.uwb

import io.flutter.embedding.engine.plugins.FlutterPlugin
import net.christiangreiner.uwb.UwbHostApi
import net.christiangreiner.uwb.UwbFlutterApi
import net.christiangreiner.uwb.UwbSessionConfig
import net.christiangreiner.uwb.UwbDevice as PigeonUwbDevice

class UwbPlugin : FlutterPlugin, UwbHostApi {
    private lateinit var uwbConnectionManager: UwbConnectionManager
    private lateinit var flutterApi: UwbFlutterApi

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = UwbFlutterApi(binding.binaryMessenger)
        uwbConnectionManager = UwbConnectionManager(
            binding.applicationContext,
            onRanging = this::onRanging,
            onDisconnected = this::onUwbSessionDisconnected
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, null)
        uwbConnectionManager.stopAllRanging()
    }

    override fun getLocalUwbAddress(callback: (Result<ByteArray>) -> Unit) {
        try {
            callback(Result.success(uwbConnectionManager.getLocalAddress()))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun isUwbSupported(): Boolean {
        // A real implementation should check for UWB support on the device.
        return true
    }

    override fun startRanging(peerAddress: ByteArray, config: UwbSessionConfig) {
        uwbConnectionManager.startRanging(peerAddress, config)
    }

    override fun stopRanging(peerAddress: String) {
        uwbConnectionManager.stopRanging(peerAddress)
    }

    override fun stopUwbSessions() {
        uwbConnectionManager.stopAllRanging()
    }

    private fun onRanging(device: PigeonUwbDevice) {
        flutterApi.onRanging(device) {}
    }

    private fun onUwbSessionDisconnected(device: PigeonUwbDevice) {
        flutterApi.onUwbSessionDisconnected(device) {}
    }
}
