package net.christiangreiner.uwb

import android.annotation.SuppressLint
import androidx.core.uwb.RangingPosition
import androidx.core.uwb.UwbClient
import androidx.core.uwb.UwbDevice
import io.reactivex.rxjava3.android.schedulers.AndroidSchedulers
import io.reactivex.rxjava3.disposables.Disposable

@SuppressLint("CheckResult")
class UwbConnectionManager(
    private val uwbClient: UwbClient,
    private val onRangingResult: (UwbRangingDevice) -> Unit,
    private val onRangingError: (String) -> Unit,
) {
    private var rangingDisposable: Disposable? = null

    fun startRanging(peerEndpoint: ByteArray) {
        if (rangingDisposable != null) {
            return
        }

        val peer = UwbDevice(peerEndpoint)
        val rangingSpec = uwbClient.prepareSession(listOf(peer))

        rangingDisposable =
            uwbClient
                .ranging(rangingSpec)
                .observeOn(AndroidSchedulers.mainThread())
                .subscribe(
                    { rangingResult ->
                        when (rangingResult) {
                            is RangingPosition -> {
                                onRangingResult(UwbDataHandler.rangingPositionToDevice(rangingResult))
                            }
                            is RangingLoss -> {
                                onRangingResult(UwbDataHandler.rangingLossToDevice(rangingResult))
                            }
                        }
                    },
                    { throwable -> onRangingError(throwable.toString()) }
                )
    }

    fun stopRanging() {
        rangingDisposable?.dispose()
        rangingDisposable = null
    }

    fun closeSession() {
        stopRanging()
        uwbClient.close()
    }
}
