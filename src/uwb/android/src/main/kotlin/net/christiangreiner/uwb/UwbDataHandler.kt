package net.christiangreiner.uwb

import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbDevice as PlatformUwbDevice // Use an alias to avoid name collision

class UwbDataHandler {

    companion object {

        fun uwbDeviceToPigeon(device: PlatformUwbDevice): UwbDevice {
            return UwbDevice.Builder()
                .setId(device.address.toString())
                .build()
        }

        fun rangingResultToPigeon(rangingResult: RangingResult): UwbDevice {
            return when (rangingResult) {
                is RangingResult.RangingResultPosition -> {
                    val position = rangingResult.position
                    val data = UwbData.Builder()
                        .setDistance(position.distance?.value?.toDouble())
                        .setAzimuth(position.azimuth?.value?.toDouble())
                        .setElevation(position.elevation?.value?.toDouble())
                        .build()
                    UwbDevice.Builder()
                        .setId(rangingResult.device.address.toString())
                        .setUwbData(data)
                        .setState(DeviceState.RANGING)
                        .build()
                }
                is RangingResult.RangingResultLoss -> {
                    UwbDevice.Builder()
                        .setId(rangingResult.device.address.toString())
                        .setState(DeviceState.LOST)
                        .build()
                }
                else -> {
                    UwbDevice.Builder()
                        .setId(rangingResult.device.address.toString())
                        .setState(DeviceState.UNKNOWN)
                        .build()
                }
            }
        }
    }
}
