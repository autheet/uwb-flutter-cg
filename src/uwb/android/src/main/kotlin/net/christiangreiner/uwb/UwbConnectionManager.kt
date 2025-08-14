package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.launchIn

class UwbConnectionManager(
    private val uwbClient: UwbClient,
    private val onRangingResult: (RangingResult) -> Unit,
    private val onRangingError: (String) -> Unit
) {
    private val coroutineScope = CoroutineScope(Dispatchers.Main)
    private var rangingJob: Job? = null

    suspend fun prepareControllerSession(accessoryAddress: ByteArray): ByteArray {
        val rangingParameters = uwbClient.prepareSession(accessoryAddress)
        return rangingParameters.shareableData
    }

    fun startRanging(shareableData: ByteArray, isController: Boolean) {
        if (rangingJob?.isActive == true) return

        val sessionFlow = if (isController) {
            uwbClient.controllerRanging(shareableData)
        } else {
            uwbClient.accessoryRanging(shareableData)
        }
        
        rangingJob = sessionFlow.onEach { rangingResult ->
            when (rangingResult) {
                is RangingResult.RangingResultPosition -> {
                    val position = rangingResult.position
                    val result = RangingResult(
                        peerAddress = position.device.address.toString(),
                        deviceName = "", 
                        distance = position.position.distance?.value?.toDouble(),
                        azimuth = position.position.azimuth?.value?.toDouble(),
                        elevation = position.position.elevation?.value?.toDouble()
                    )
                    onRangingResult(result)
                }
                is RangingResult.RangingResultLoss -> {
                   // This is handled by the BLE layer in Dart.
                }
            }
        }.launchIn(coroutineScope)
    }

    fun stopRanging() {
        rangingJob?.cancel()
        rangingJob = null
    }
}
