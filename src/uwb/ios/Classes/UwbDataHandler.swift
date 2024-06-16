import Flutter
import NearbyInteraction

class UwbDataHandler: NSObject, FlutterStreamHandler {
    private var _eventSink: FlutterEventSink?
    
    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        _eventSink = eventSink
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        _eventSink = nil
        return nil
    }
    
    func sendData(
        peerId: String,
        name: String,
        distance: Float?,
        direction: simd_float3?,
        horizontalAngle: Float?,
        azimuth: Float?,
        elevation: Float?,
        deviceType: DeviceType
    ) {
        let uwbDataDict = [
            "id": peerId,
            "name": name,
            "distance": distance ?? nil,
            "directionX": direction?.x ?? nil,
            "directionY": direction?.y ?? nil,
            "directionZ": direction?.z ?? nil,
            "horizontalAngle": horizontalAngle ?? nil,
            "azimuth": azimuth ?? nil,
            "elevation": elevation ?? nil,
            "deviceType": deviceType.rawValue
        ] as [String : Any?]
        
        var jsonString: String = ""
        
        // convert to JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: uwbDataDict, options: [])
            jsonString = String(data: jsonData, encoding: .ascii) ?? ""
        } catch {
            // Print error
            NSLog("ERROR parsing JSON")
        }
        
        _eventSink?(jsonString)
    }
}
