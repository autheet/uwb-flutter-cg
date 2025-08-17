
import Flutter
import UIKit
import NearbyInteraction
import Foundation

// By default, FlutterError does not conform to the Swift Error protocol.
// We can make it conform by adding an extension.
extension FlutterError: Error {}

extension Data {
    func toHexString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
    func toFlutterStandardTypedData() -> FlutterStandardTypedData {
        return FlutterStandardTypedData(bytes: self)
    }
}

public class UwbPlugin: NSObject, FlutterPlugin, UwbHostApi, NISessionDelegate {
    
    var niSession: NISession?
    var flutterApi: UwbFlutterApi?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = UwbPlugin()
        UwbHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        instance.flutterApi = UwbFlutterApi(binaryMessenger: registrar.messenger())
    }

    // MARK: - Session Management
    
    public func start(deviceName: String, serviceUUIDDigest: String) async throws {
        NSLog("[UWB Native iOS] Initializing NISession.")
        niSession = NISession()
        niSession?.delegate = self
    }

    public func stop() async throws {
        NSLog("[UWB Native iOS] Invalidating NISession.")
        niSession?.invalidate()
        niSession = nil
    }

    // MARK: - iOS Peer-to-Peer Ranging (Apple devices only)
    
    public func startIosController() async throws -> FlutterStandardTypedData {
        NSLog("[UWB Native iOS] Generating discovery token for Apple Peer-to-Peer.")
        guard let token = niSession?.discoveryToken else {
            throw FlutterError(code: "UWB_ERROR", message: "Missing discovery token for Peer-to-Peer", details: nil)
        }
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true).toFlutterStandardTypedData()
    }

    public func startIosAccessory(token: FlutterStandardTypedData) async throws {
        NSLog("[UWB Native iOS] Starting accessory role with Apple Peer token.")
        guard let discoveryToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: token.data) else {
            throw FlutterError(code: "UWB_ERROR", message: "Invalid discovery token data for Peer-to-Peer", details: nil)
        }
        let config = NINearbyPeerConfiguration(peerToken: discoveryToken)
        niSession?.run(config)
    }

    // MARK: - FiRa Accessory Ranging (Cross-Platform)

    public func getAccessoryAddress() async throws -> FlutterStandardTypedData {
        NSLog("[UWB Native iOS] Getting accessory address (discovery token).")
        guard let token = niSession?.discoveryToken else {
            throw FlutterError(code: "UWB_ERROR", message: "Missing discovery token for Accessory role", details: nil)
        }
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true).toFlutterStandardTypedData()
    }

    public func generateControllerConfig(accessoryAddress: FlutterStandardTypedData, sessionKeyInfo: FlutterStandardTypedData, sessionId: Int64) async throws -> UwbConfig {
        NSLog("[UWB Native iOS] Generating FiRa configuration for accessory.")
        guard let token = niSession?.discoveryToken else {
            throw FlutterError(code: "UWB_ERROR", message: "Missing discovery token for Controller role", details: nil)
        }
        
        do {
            let accessoryData = accessoryAddress.data
            let config = try NINearbyAccessoryConfiguration(data: accessoryData)
            
            niSession?.run(config)
            
            let uwbConfig = UwbConfig(
                uwbConfigId: 1, // CONFIG_UNICAST_DS_TWR
                sessionId: sessionId,
                sessionKeyInfo: sessionKeyInfo, // Pass the FlutterStandardTypedData directly
                channel: 9, 
                preambleIndex: 10,
                peerAddress: try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true).toFlutterStandardTypedData()
            )
            return uwbConfig
        } catch {
            throw FlutterError(code: "UWB_ERROR", message: "Failed to generate controller configuration: \(error.localizedDescription)", details: nil)
        }
    }

    public func startAccessoryRanging(config: UwbConfig) async throws {
        NSLog("[UWB Native iOS] Starting accessory ranging with config from controller.")
        // This is largely a placeholder on iOS, as the session is started by `generateControllerConfig`
        // when it calls `niSession.run()`. This function must exist to satisfy the protocol.
    }
    
    // MARK: - NISessionDelegate
    
    public func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        for object in nearbyObjects {
            var peerAddress = ""
            if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: object.discoveryToken, requiringSecureCoding: true) {
                peerAddress = tokenData.toHexString()
            }
            let result = RangingResult(
                peerAddress: peerAddress,
                deviceName: "", // Device name is handled in the Dart layer
                distance: object.distance.map { Double($0) },
                azimuth: object.direction.map { Double($0.x) },
                elevation: object.direction.map { Double($0.y) }
            )
            flutterApi?.onRangingResult(result: result, completion: { _ in })
        }
    }
    
    public func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        // Implementation can be added here if needed
    }
    
    public func sessionWasSuspended(_ session: NISession) {
        NSLog("[UWB Native iOS] NI session was suspended.")
    }
    
    public func sessionSuspensionEnded(_ session: NISession) {
        NSLog("[UWB Native iOS] NI session suspension ended.")
    }
    
    public func session(_ session: NISession, didInvalidateWith error: Error) {
        NSLog("[UWB Native iOS] NI session did invalidate with error: %@", error.localizedDescription)
        flutterApi?.onRangingError(error: error.localizedDescription, completion: { _ in })
    }
}
