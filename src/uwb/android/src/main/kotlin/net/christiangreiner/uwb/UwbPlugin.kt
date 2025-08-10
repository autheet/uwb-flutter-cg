package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.UwbManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

// Correctly import all necessary Pigeon-generated classes
import net.christiangreiner.uwb.UwbHostApi
import net.christiangreiner.uwb.UwbFlutterApi
import net.christiangreiner.uwb.UwbDevice
import net.christiangreiner.uwb.UwbSessionConfig
import net.christiangreiner.uwb.UwbData
import net.christiangreiner.uwb.Direction3D
import net.christiangreiner.uwb.DeviceState
import net.christiangreiner.uwb.DeviceType
import net.christiangreiner.uwb.PermissionAction
import java.lang.Exception


class UwbPlugin : FlutterPlugin, UwbHostApi, UwbConnectionListener {
    private var uwbManager: UwbManager? = null
    private lateinit var flutterApi: UwbFlutterApi
    private val coroutineScope = CoroutineScope(Dispatchers.Main)
    private var uwbConnectionManager: UwbConnectionManager? = null
    private lateinit var applicationContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = UwbFlutterApi(binding.binaryMessenger)
        applicationContext = binding.applicationContext
        try {
            uwbManager = UwbManager.createInstance(applicationContext)
        } catch (e: Exception) {
            // UWB not available on this device.
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
        if (uwbConnectionManager == null) {
            uwbConnectionManager = UwbConnectionManager(applicationContext, uwbManager!!, this, coroutineScope)
        }
        coroutineScope.launch {
            val address = uwbConnectionManager!!.getLocalAddress()
            callback(Result.success(address.address))
        }
    }

    override fun startRanging(peerAddress: ByteArray, config: UwbSessionConfig) {
        if (uwbManager == null) return
        if (uwbConnectionManager == null) {
             uwbConnectionManager = UwbConnectionManager(applicationContext, uwbManager!!, this, coroutineScope)
        }
        
        val rangingParameters = androidx.core.uwb.RangingParameters(
            uwbConfigType = androidx.core.uwb.RangingParameters.UWB_CONFIG_ID_1,
            sessionId = config.sessionId.toInt(),
            sessionKeyInfo = config.sessionKeyInfo,
            complexChannel = null,
            peerDevices = listOf(androidx.core.uwb.UwbDevice.createForAddress(peerAddress)),
            updateRateType = androidx.core.uwb.RangingParameters.RANGING_UPDATE_RATE_AUTOMATIC
        )
        uwbConnectionManager!!.startRanging(rangingParameters, config)
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

    // --- UwbConnectionListener Implementation ---

    override fun onRangingResult(device: UwbDevice) {
        flutterApi.onRanging(device) {}
    }

    override fun onRangingError(error: Exception) {
        // Here you can decide how to report errors to the Flutter side.
        // For now, we'll just log them.
        println("UWB Ranging Error: ${error.message}")
    }

    override fun onPeerDisconnected(device: UwbDevice) {
        flutterApi.onUwbSessionDisconnected(device) {}
    }
}
