
import Flutter
import UIKit
import NearbyInteraction
import Foundation // Needed for JSON and logging

// By default, FlutterError does not conform to the Swift Error protocol.
// We can make it conform by adding an extension.
extension FlutterError: Error {}

public class UwbPlugin: NSObject, FlutterPlugin, UwbHostApi, NISessionDelegate {
    
    var niSession: NISession?
    var flutterApi: UwbFlutterApi?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = UwbPlugin()
        UwbHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        instance.flutterApi = UwbFlutterApi(binaryMessenger: registrar.messenger())
    }

    // MARK: - Session Management
    
    public func start(deviceName: String, serviceUUIDDigest: String, completion: @escaping (Result<Void, Error>) -> Void) {
        NSLog("[UWB Native iOS] Initializing NISession.")
        niSession = NISession()
        niSession?.delegate = self
        completion(.success(Void()))
    }

    public func stop(completion: @escaping (Result<Void, Error>) -> Void) {
        NSLog("[UWB Native iOS] Invalidating NISession.")
        niSession?.invalidate()
        niSession = nil
        completion(.success(Void()))
    }

    // MARK: - iOS Peer-to-Peer Ranging (Apple devices only)
    
    // This uses NINearbyPeerConfiguration and is kept for iOS-iOS functionality.
    public func startIosController(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        NSLog("[UWB Native iOS] Generating discovery token for Apple Peer-to-Peer.")
        guard let token = niSession?.discoveryToken else {
            return completion(.failure(FlutterError(code: "UWB_ERROR", message: "Missing discovery token for Peer-to-Peer", details: nil)))
        }
        do {
            let tokenData = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            completion(.success(FlutterStandardTypedData(bytes: tokenData)))
        } catch {
            completion(.failure(FlutterError(code: "UWB_ERROR", message: "Failed to archive discovery token: \(error.localizedDescription)", details: nil)))
        }
    }

    public func startIosAccessory(token: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        NSLog("[UWB Native iOS] Starting accessory role with Apple Peer token.")
        do {
            guard let discoveryToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: token.data) else {
                return completion(.failure(FlutterError(code: "UWB_ERROR", message: "Invalid discovery token data for Peer-to-Peer", details: nil)))
            }
            let config = NINearbyPeerConfiguration(peerToken: discoveryToken)
            niSession?.run(config)
            completion(.success(Void()))
        } catch {
            completion(.failure(FlutterError(code: "UWB_ERROR", message: "Failed to start accessory session: \(error.localizedDescription)", details: nil)))
        }
    }

    // MARK: - FiRa Accessory Ranging (Cross-Platform)

    // Step 1: An accessory (iOS) gets its own UWB address to share with a controller.
    public func getAccessoryAddress(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        NSLog("[UWB Native iOS] Getting accessory address (discovery token).")
        guard let token = niSession?.discoveryToken else {
            return completion(.failure(FlutterError(code: "UWB_ERROR", message: "Missing discovery token for Accessory role", details: nil)))
        }
        do {
            let tokenData = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            completion(.success(FlutterStandardTypedData(bytes: tokenData)))
        } catch {
             completion(.failure(FlutterError(code: "UWB_ERROR", message: "Failed to archive accessory token: \(error.localizedDescription)", details: nil)))
        }
    }

    // Step 2: A controller (iOS) takes an accessory's address and generates the full config for the session.
    public func generateControllerConfig(accessoryAddress: FlutterStandardTypedData, sessionKeyInfo: FlutterStandardTypedData, sessionId: Int64, completion: @escaping (Result<UwbConfig, Error>) -> Void) {
        NSLog("[UWB Native iOS] Generating FiRa configuration for accessory.")
        guard let token = niSession?.discoveryToken else {
             return completion(.failure(FlutterError(code: "UWB_ERROR", message: "Missing discovery token for Controller role", details: nil)))
        }
        
        do {
            // Create the accessory configuration using the data from the Android accessory.
            let accessoryData = accessoryAddress.data
            let config = try NINearbyAccessoryConfiguration(data: accessoryData)
            
            // Run the session to get the shareable configuration data.
            niSession?.run(config)
            
            // The UWBConfig object contains all the parameters the accessory needs.
            // We are explicitly setting the FiRa-compliant parameters.
            let uwbConfig = UwbConfig(
                uwbConfigId: 1, // CONFIG_UNICAST_DS_TWR
                sessionId: sessionId,
                sessionKeyInfo: sessionKeyInfo.data,
                channel: 9, 
                preambleIndex: 10,
                peerAddress: try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            )
            completion(.success(uwbConfig))
        } catch {
            completion(.failure(FlutterError(code: "UWB_ERROR", message: "Failed to generate controller configuration: \(error.localizedDescription)", details: nil)))
        }
    }

    // Step 3: An accessory (iOS) receives the full config from the controller and starts ranging.
    public func startAccessoryRanging(config: UwbConfig, completion: @escaping (Result<Void, Error>) -> Void) {
        NSLog("[UWB Native iOS] Starting accessory ranging with config from controller.")
        // On iOS, starting the session is handled by `generateControllerConfig` when it calls `niSession.run()`.
        // This method is primarily a placeholder for the accessory role on iOS but could be used
        // for future state updates if needed.
        completion(.success(Void()))
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
                distance: Double(object.distance ?? 0),
                azimuth: Double(object.direction?.x ?? 0),
                elevation: Double(object.direction?.y ?? 0)
            )
            flutterApi?.onRangingResult(result: result, completion: { _ in })
        }
    }
    
    public func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        // ... (implementation unchanged)
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

extension Data {
    func toHexString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
