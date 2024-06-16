package net.christiangreiner.uwb

import UwbDevice
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject

class UwbDataHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }

    fun sendData(device: UwbDevice) {
        var data = HashMap<String, Any>()
        data["id"] = device.id
        data["name"] = device.name!!
        data["distance"] = device.uwbData?.distance ?: 0f
        data["azimuth"] = device.uwbData?.azimuth ?: 0f
        data["elevation"] = device.uwbData?.elevation ?: 0f
        data["deviceType"] = device.deviceType.raw
        var jsonString = JSONObject(data as Map<String, Any>?).toString()
        this.eventSink!!.success(jsonString)
    }
}

