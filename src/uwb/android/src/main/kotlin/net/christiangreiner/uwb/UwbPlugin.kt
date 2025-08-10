package net.christiangreiner.uwb

import androidx.core.uwb.UwbManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.UUID
import net.christiangreiner.uwb.UwbHostApi // Import Pigeon-generated API
import net.christiangreiner.uwb.UwbFlutterApi // Import Pigeon-generated API
import net.christiangreiner.uwb.UwbDevice // Import Pigeon-generated data models
import net.christiangreiner.uwb.UwbSessionConfig // Import Pigeon-generated data models
import net.christiangreiner.uwb.UwbData // Import Pigeon-generated data models
import net.christiangreiner.uwb.Direction3D // Import Pigeon-generated data models
import net.christiangreiner.uwb.DeviceState // Import Pigeon-generated data models
import net.christiangreiner.uwb.DeviceType // Import Pigeon-generated data models

class UwbPlugin : FlutterPlugin, UwbHostApi {
    private var uwbManager: UwbManager? = null
    private lateinit var flutterApi: UwbFlutterApi
    private val coroutineScope = CoroutineScope(Dispatchers.Main)
    private var uwbConnectionManager: UwbConnectionManager? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = UwbFlutterApi(binding.binaryMessenger)
        try {
            uwbManager = UwbManager.createInstance(binding.applicationContext)
        } catch (e: Exception) {
            // Handle exceptions if UWB is not available on the device
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, null)
    }

    override fun getLocalUwbAddress(callback: (Result<ByteArray>) -> Unit) {
        if (uwbManager == null) {
            callback(Result.failure(Exception("UWB not available.")))
            return
        }
        uwbConnectionManager = UwbConnectionManager(uwbManager!!, flutterApi)
        coroutineScope.launch {
            val address = uwbConnectionManager!!.getLocalAddress()
            callback(Result.success(address.address))
        }
    }

    override fun startRanging(peerAddress: ByteArray, config: UwbSessionConfig) {
        if (uwbManager == null) return
        uwbConnectionManager = UwbConnectionManager(uwbManager!!, flutterApi)
        
        val rangingParameters = androidx.core.uwb.RangingParameters(
            uwbConfigType = androidx.core.uwb.RangingParameters.UWB_CONFIG_ID_1,
            sessionId = config.sessionId.toInt(),
            sessionKeyInfo = config.sessionKeyInfo,
            complexChannel = null,
            peerDevices = listOf(androidx.core.uwb.UwbDevice.createForAddress(peerAddress)),
            rangingUpdateRate = androidx.core.uwb.RangingParameters.RANGING_UPDATE_RATE_AUTOMATIC
        )
        uwbConnectionManager!!.startRanging(rangingParameters)
    }

    override fun stopRanging(peerAddress: String) {
        uwbConnectionManager?.stopRanging()
    }

    override fun stopUwbSessions() {
        uwbConnectionManager?.stopRanging()
    }

    override fun isUwbSupported(): Boolean {
        return uwbManager != null
    }
}
