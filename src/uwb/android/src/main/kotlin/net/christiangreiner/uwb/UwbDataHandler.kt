package net.christiangreiner.uwb

import androidx.core.uwb.RangingLoss
import androidx.core.uwb.RangingPosition

class UwbDataHandler {

    companion object {
        fun rangingPositionToDevice(rangingPosition: RangingPosition): UwbRangingDevice {
            val position = rangingPosition.position
            val data = UwbRangingData.Builder()
                .setDistance(position.distance?.value?.toDouble())
                .setAzimuth(position.azimuth?.value?.toDouble())
                .setElevation(position.elevation?.value?.toDouble())
                .build()
            return UwbRangingDevice.Builder()
                .setId(rangingPosition.device.address.toString())
                .setState(UwbDeviceState.RANGING)
                .setData(data)
                .build()
        }

        fun rangingLossToDevice(rangingLoss: RangingLoss): UwbRangingDevice {
            return UwbRangingDevice.Builder()
                .setId(rangingLoss.device.address.toString())
                .setState(UwbDeviceState.LOST)
                .build()
        }
    }
}
