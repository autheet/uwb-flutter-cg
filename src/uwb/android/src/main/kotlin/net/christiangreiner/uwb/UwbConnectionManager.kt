package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

class UwbConnectionManager(
    private val context: Context,
    private val uwbClient: UwbClient,
    private val onRangingResult: (net.christiangreiner.uwb.RangingResult) -> Unit,
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

        rangingJob = coroutineScope.launch {
            try {
                val sessionFlow = if (isController) {
                    uwbClient.controllerRanging(shareableData)
                } else {
                    uwbClient.accessoryRanging(shareableData)
                }
                
                sessionFlow.collect { rangingResult ->
                    when (rangingResult) {
                        is RangingResult.RangingResultPosition -> {
                            val position = rangingResult.position
                            val result = net.christiangreiner.uwb.RangingResult(
                                peerAddress = position.device.address.toString(),
                                deviceName = "",
                                distance = position.position.distance?.value?.toDouble(),
                                azimuth = position.position.azimuth?.value?.toDouble(),
                                elevation = position.position.elevation?.value?.toDouble()
                            )
                            onRangingResult(result)
                        }
                        is RangingResult.RangingResultLoss -> {
                           // This is now handled by the BLE layer in Dart
                        }
                    }
                }
            } catch (e: Exception) {
                onRangingError(e.message ?: "Unknown Ranging Error")
            }
        }
    }

    fun stopRanging() {
        rangingJob?.cancel()
        rangingJob = null
        coroutineScope.cancel()
    }
}
