package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.UwbClient
import androidx.core.uwb.RangingResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.launchIn
import java.nio.ByteBuffer

// This class manages a single UWB ranging session.
class UwbConnectionManager(
    private val uwbClient: UwbClient,
    private val onRangingResult: (RangingResult) -> Unit,
    private val onRangingError: (String) -> Unit
) {
    private val coroutineScope = CoroutineScope(Dispatchers.Main)
    private var rangingJob: Job? = null

    // This is called by the controller to get the shareable configuration data.
    suspend fun prepareControllerSession(accessoryAddress: ByteArray): ByteArray {
        val rangingParameters = uwbClient.prepareSession(accessoryAddress)
        return rangingParameters.shareableData
    }

    // This starts the ranging session for either the controller or accessory.
    fun startRanging(shareableData: ByteArray, isController: Boolean) {
        if (rangingJob?.isActive == true) {
            return // Ranging is already in progress
        }

        val sessionFlow = if (isController) {
            uwbClient.controllerRanging(shareableData)
        } else {
            uwbClient.accessoryRanging(shareableData)
        }

        rangingJob = sessionFlow
            .onEach {
                when (it) {
                    is RangingResult.RangingResultPosition -> {
                        val position = it.position
                        // Create an instance of our Pigeon-generated RangingResult class.
                        val result = RangingResult(
                            peerAddress = position.device.address.toString(),
                            deviceName = "", // Device name is handled in the Dart layer
                            distance = position.position.distance?.value?.toDouble(),
                            azimuth = position.position.azimuth?.value?.toDouble(),
                            elevation = position.position.elevation?.value?.toDouble()
                        )
                        onRangingResult(result)
                    }
                    is RangingResult.RangingResultLoss -> {
                        // The BLE layer in Dart is now responsible for handling lost peers.
                    }
                }
            }
            .launchIn(coroutineScope)
    }

    fun stopRanging() {
        rangingJob?.cancel()
        rangingJob = null
    }
}
