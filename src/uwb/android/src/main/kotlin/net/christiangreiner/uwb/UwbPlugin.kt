package net.christiangreiner.uwb

import android.annotation.SuppressLint
import android.content.Context
import androidx.core.uwb.RangingParameters
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbAddress
import androidx.core.uwb.UwbClientSessionScope
import androidx.core.uwb.UwbManager
import androidx.core.uwb.UwbDevice
import androidx.core.uwb.UwbComplexChannel
import androidx.core.uwb.rxjava3.controleeSessionScopeSingle
import androidx.core.uwb.rxjava3.controllerSessionScopeSingle
import androidx.core.uwb.rxjava3.rangingResultsObservable
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.reactivex.rxjava3.disposables.Disposable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.rx3.await // If using await() with RxJava Singles
import kotlinx.coroutines.cancel

// Import the generated Pigeon classes
import net.christiangreiner.uwb.RangingResult as PigeonRangingResult

class UwbPlugin : FlutterPlugin, UwbHostApi {

    private var appContext: Context? = null
    private var flutterApi: UwbFlutterApi? = null
    private val pluginScope = CoroutineScope(Dispatchers.Main) // CoroutineScope for plugin operations
    
    private var uwbManager: UwbManager? = null
    private var clientSessionScope: UwbClientSessionScope? = null
    private var rangingDisposable: Disposable? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        UwbHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = UwbFlutterApi(binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UwbHostApi.setUp(binding.binaryMessenger, null)
        appContext = null
        flutterApi = null
        pluginScope.cancel() // Cancel the scope when the plugin is detached
    }
    
    // --- Session Management ---
    override fun start(deviceName: String, serviceUUIDDigest: String, callback: (Result<Unit>) -> Unit) {
        val context = appContext ?: return callback(Result.failure(Exception("AppContext is null")))
        uwbManager = UwbManager.createInstance(context)
        callback(Result.success(Unit))
    }

    override fun stop(callback: (Result<Unit>) -> Unit) {
        rangingDisposable?.dispose()
        rangingDisposable = null
        pluginScope.cancel() // Cancel the scope
        clientSessionScope = null
        uwbManager = null
        callback(Result.success(Unit))
    }

    // --- FiRa Accessory Ranging (Android Implementation) ---

    override fun getAccessoryAddress(callback: (Result<ByteArray>) -> Unit) {
        val manager = uwbManager ?: return callback(Result.failure(Exception("UwbManager not initialized")))
        pluginScope.launch {
            try {
                val sessionScope = manager.controleeSessionScopeSingle().await() // Use await() for Single
                clientSessionScope = sessionScope
                callback(Result.success(sessionScope.localAddress.address))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun generateControllerConfig(accessoryAddress: ByteArray, sessionKeyInfo: ByteArray, sessionId: Long, callback: (Result<UwbConfig>) -> Unit) {
        val manager = uwbManager ?: return callback(Result.failure(Exception("UwbManager not initialized")))
        pluginScope.launch {
            try {
                val sessionScope = manager.controllerSessionScopeSingle().await() // Use await() for Single
                clientSessionScope = sessionScope
                val configId = RangingParameters.CONFIG_UNICAST_DS_TWR
                val channel = 9
                val preamble = 10
                val complexChannel = UwbComplexChannel(channel, preamble)
                val peerAddress = UwbAddress(accessoryAddress)

                val rangingParameters = RangingParameters(
                    uwbConfigType = configId,
                    sessionId = sessionId.toInt(),
                    subSessionId = 0,
                    sessionKeyInfo = sessionKeyInfo,
                    subSessionKeyInfo = null,
                    complexChannel = complexChannel,
                    peerDevices = listOf(UwbDevice.createForAddress(peerAddress.address)),
                    updateRateType = RangingParameters.RANGING_UPDATE_RATE_AUTOMATIC
                )

                rangingDisposable?.dispose()
                rangingDisposable = sessionScope.rangingResultsObservable(rangingParameters)
                    .subscribe(
                        { handleRangingResult(it) },
                        { error -> flutterApi?.onRangingError(error.toString()) {} }
                    )

                val config = UwbConfig(
                    uwbConfigId = configId.toLong(),
                    sessionId = sessionId,
                    sessionKeyInfo = sessionKeyInfo,
                    channel = channel.toLong(),
                    preambleIndex = preamble.toLong(),
                    peerAddress = sessionScope.localAddress.address
                )
                callback(Result.success(config))
            } catch (e: Exception) { callback(Result.failure(e)) }
        }
    }

    override fun startAccessoryRanging(config: UwbConfig, callback: (Result<Unit>) -> Unit) {
        pluginScope.launch {
            try {
                val sessionScope = clientSessionScope ?: return@launch callback(Result.failure(Exception("UwbClientSessionScope not initialized.")))
                val controllerAddress = UwbAddress(config.peerAddress)
                val complexChannel = UwbComplexChannel(config.channel.toInt(), config.preambleIndex.toInt())

                val rangingParameters = RangingParameters(
                    uwbConfigType = config.uwbConfigId.toInt(),
                    sessionId = config.sessionId.toInt(),
                    subSessionId = 0,
                    sessionKeyInfo = config.sessionKeyInfo,
                    subSessionKeyInfo = null,
                    complexChannel = complexChannel,
                    peerDevices = listOf(UwbDevice.createForAddress(controllerAddress.address)),
                    updateRateType = RangingParameters.RANGING_UPDATE_RATE_AUTOMATIC
                )

                rangingDisposable?.dispose()
                rangingDisposable = sessionScope.rangingResultsObservable(rangingParameters)
                    .subscribe(
                        { handleRangingResult(it) },
                        { error -> flutterApi?.onRangingError(error.toString()) {} }
                    )
                callback(Result.success(Unit))
            } catch (e: Exception) { callback(Result.failure(e)) }
        }
    }
    
    private fun handleRangingResult(result: RangingResult) {
        when (result) {
            is RangingResult.RangingResultPosition -> {
                val pigeonResult = PigeonRangingResult(
                    result.device.address.toString(),
                    "", 
                    result.position.distance?.value?.toDouble(),
                    result.position.azimuth?.value?.toDouble(),
                    result.position.elevation?.value?.toDouble()
                )
                flutterApi?.onRangingResult(pigeonResult) {}
            }
            is RangingResult.RangingResultPeerDisconnected -> {
                flutterApi?.onPeerLost("", result.device.address.toString()) {}
            }
        }
    }

    // --- iOS Peer-to-Peer Ranging (Not used on Android) ---
    override fun startIosController(callback: (Result<ByteArray>) -> Unit) {
        callback(Result.failure(Exception("This method is for iOS only.")))
    }

    override fun startIosAccessory(token: ByteArray, callback: (Result<Unit>) -> Unit) {
        callback(Result.failure(Exception("This method is for iOS only.")))
    }
}