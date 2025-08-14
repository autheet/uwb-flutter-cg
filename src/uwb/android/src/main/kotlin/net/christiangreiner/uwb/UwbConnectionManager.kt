package net.christiangreiner.uwb

import android.content.Context
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbClient
import androidx.core.uwb.UwbControllerSessionScope
import androidx.core.uwb.UwbManager
import androidx.core.uwb.UwbAccessorySessionScope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

class UwbConnectionManager(
    private val context: Context,
    private val uwbClient: UwbClient,
    private val onRangingResult: (RangingResult) -> Unit,
    private val onRangingError: (String) -> Unit
) {
    private var sessionScope: CoroutineScope? = null
    private var rangingJob: Job? = null

    suspend fun prepareControllerSession(accessoryAddress: ByteArray): ByteArray {
        val scope = UwbManager.controllerSessionScope(uwbClient)
        this.sessionScope = scope
        return scope.prepareSession(accessoryAddress)
    }

    fun startRanging(shareableData: ByteArray, isController: Boolean) {
        val scopeToUse = sessionScope ?: return

        rangingJob = if (isController) {
            (scopeToUse as UwbControllerSessionScope).rangingResults
                .onEach { onRangingResult(it.toRangingResult()) }
                .catch { e -> onRangingError(e.toString()) }
                .launchIn(scopeToUse)
        } else {
            // For the accessory, we need to create a new session scope
            val accessoryScope = UwbManager.accessorySessionScope(uwbClient)
            this.sessionScope = accessoryScope
            accessoryScope.rangingResults
                .onEach { onRangingResult(it.toRangingResult()) }
                .catch { e -> onRangingError(e.toString()) }
                .launchIn(accessoryScope)
        }
    }

    fun stopRanging() {
        rangingJob?.cancel()
        sessionScope?.cancel()
        rangingJob = null
        sessionScope = null
    }

    private fun RangingResult.toRangingResult(): RangingResult {
        val position = this.position
        val distance = position?.distance?.value
        val azimuth = position?.azimuth?.value
        val elevation = position?.elevation?.value
        return RangingResult(
            address = this.device.address.toString(),
            distance = distance?.toDouble() ?: 0.0,
            azimuth = azimuth?.toDouble() ?: 0.0,
            elevation = elevation?.toDouble() ?: 0.0,
        )
    }
}
