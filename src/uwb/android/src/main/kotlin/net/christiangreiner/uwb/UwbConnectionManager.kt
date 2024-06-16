package net.christiangreiner.uwb

import android.content.Context
import android.util.Log
import androidx.core.uwb.RangingParameters
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbAddress
import androidx.core.uwb.UwbComplexChannel
import androidx.core.uwb.UwbControleeSessionScope
import androidx.core.uwb.UwbControllerSessionScope
import androidx.core.uwb.UwbDevice
import androidx.core.uwb.UwbManager
import androidx.core.uwb.rxjava3.controleeSessionScopeSingle
import androidx.core.uwb.rxjava3.controllerSessionScopeSingle
import androidx.core.uwb.rxjava3.rangingResultsFlowable
import io.reactivex.rxjava3.core.Flowable
import io.reactivex.rxjava3.core.Single
import io.reactivex.rxjava3.disposables.Disposable
import io.reactivex.rxjava3.subscribers.DisposableSubscriber
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit

class UwbConnectionManager(context: Context, private var appCoroutineScope: CoroutineScope) {
    private var uwbManager: UwbManager

    private val LOG_TAG: String = "UWB Manager"

    // Callbacks
    var onUwbRangingStarted: ((String) -> Unit)? = null

    private val sessionKeyInfo : ByteArray = byteArrayOf(0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08)
    private val uwbChannel: Int = 9

    // TODO: Each Session should have an own contollerSessionScope
    private var controllerSessionScopeSingle: Single<UwbControllerSessionScope>? = null
    private var controleeSessionScopeSingle: Single<UwbControleeSessionScope>? = null
    private var controleeSessionScope: UwbControleeSessionScope? = null
    private var controllerSessionScope: UwbControllerSessionScope? = null

    // Mapping Endpoint ID and Ranging Job
    private var rangingJobs = HashMap<String, Job>()

    // Maps the Endpoint ID and the UWB Session Disposable
    private var disposableMap = HashMap<String, Disposable?>()

    var localUwbAddress: UwbAddress? = null
    private var isRanging: Boolean = false

    init {
        this.uwbManager = UwbManager.createInstance(context)
    }

    fun isDeviceRanging(deviceId: String) : Boolean {
        return this.disposableMap.containsKey(deviceId)
    }

    fun getControllerSessionScope() : UwbControllerSessionScope? {
        return this.controllerSessionScope
    }

    fun getControleeSessionScope() : UwbControleeSessionScope? {
        return this.controleeSessionScope
    }

    fun isRanging(): Boolean {
        return this.isRanging
    }

    fun createControllerSession() {
        this.controllerSessionScopeSingle = this.uwbManager.controllerSessionScopeSingle()
        this.controllerSessionScope = controllerSessionScopeSingle!!.blockingGet()
        this.localUwbAddress = controllerSessionScope!!.localAddress
    }

    fun createControleeSession() {
        this.controleeSessionScopeSingle = this.uwbManager.controleeSessionScopeSingle()
        this.controleeSessionScope = controleeSessionScopeSingle!!.blockingGet()
        this.localUwbAddress = controleeSessionScope!!.localAddress
    }

    fun startRanging(endpointId: String, endpointUwbAddress: UwbAddress, sessionKey: Int, preambleIndex: Int) : Flow<RangingResult> = channelFlow{
        if (disposableMap.containsKey(endpointId)) {
            // throw Exception
            Log.e(LOG_TAG, "Ranging with $endpointId exists.")
        }

        val rangingJob = appCoroutineScope.launch {
            var sessionFlow: Flowable<RangingResult>? = null
            var rangingParams = RangingParameters(
                uwbConfigType = RangingParameters.CONFIG_UNICAST_DS_TWR,
                sessionId = sessionKey,
                subSessionId = 0,
                sessionKeyInfo = sessionKeyInfo,
                subSessionKeyInfo = null,
                complexChannel = UwbComplexChannel(uwbChannel, preambleIndex),
                peerDevices = listOf(UwbDevice(endpointUwbAddress)),
                updateRateType = RangingParameters.RANGING_UPDATE_RATE_AUTOMATIC,
            )

            if (controllerSessionScope != null) {
                sessionFlow = controllerSessionScope!!.rangingResultsFlowable(rangingParams)
            } else {
                Log.e(LOG_TAG, "controllerSessionScope is null!")
            }

            if (controleeSessionScope != null) {
                sessionFlow = controleeSessionScope!!.rangingResultsFlowable(rangingParams)
            } else {
                Log.e(LOG_TAG, "controleeSessionScope is null!")
            }

            if (controllerSessionScope == null && controleeSessionScope == null)
            {
                // TODO Deal with error
                Log.e(LOG_TAG, "RANGING FAIL, both controller and controlee are null")
            }

            Log.i(LOG_TAG, "Start session with config: preambleIndex: $preambleIndex, Local Address: $localUwbAddress, Peer Address: $endpointUwbAddress, Session Key: $sessionKey")

            var disposable = sessionFlow!!
                .delay(1, TimeUnit.SECONDS)
                .subscribeWith(object : DisposableSubscriber<RangingResult>() {
                        override fun onStart() {
                            Log.i(LOG_TAG, "UWB Ranging started")
                            isRanging = true
                            request(1)
                        }

                        override fun onNext(rangingResult: RangingResult) {
                            appCoroutineScope.launch  {
                                send(rangingResult)
                            }

                            when (rangingResult) {
                                is RangingResult.RangingResultPeerDisconnected -> {
                                    stopRanging(endpointId)
                                }
                            }
                            request(Long.MAX_VALUE)
                        }

                        override fun onError(t: Throwable) {
                            Log.e(LOG_TAG,"Ranging exists already.")
                            t.printStackTrace()
                            isRanging = false
                        }

                        override fun onComplete() {
                            Log.i(LOG_TAG, "UWB Ranging session completed.")
                            isRanging = false
                        }
                    }
                )
            disposableMap[endpointId] = disposable
        }
        rangingJobs[endpointId] = rangingJob
        onUwbRangingStarted?.invoke(endpointId)

        awaitClose {
            rangingJob.cancel()
        }
    }

    fun stopRanging(endpointId: String) {
        if (disposableMap.containsKey(endpointId)) {
            disposableMap[endpointId]?.dispose()
            disposableMap.remove(endpointId)
        }
        if (rangingJobs.containsKey(endpointId)) {
            rangingJobs[endpointId]?.cancel()
            rangingJobs.remove(endpointId)
        }
        controleeSessionScope = null
        controllerSessionScope = null
        controleeSessionScopeSingle = null
        controllerSessionScopeSingle = null
        isRanging = false
        Log.i(LOG_TAG, "UWB Session with $endpointId stopped.")
    }

    fun stopRanging() {
        rangingJobs.forEach { (key, _) ->
            stopRanging(key)
        }
        rangingJobs.clear()
    }
}