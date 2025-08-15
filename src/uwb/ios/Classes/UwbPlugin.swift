
import Flutter
import UIKit
import NearbyInteraction

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

    // The deviceName and serviceUUIDDigest are not used on iOS, as BLE is handled by the Flutter layer.
    public func start(deviceName: String, serviceUUIDDigest: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("[UWB Native iOS] Initializing NISession.")
        niSession = NISession()
        niSession?.delegate = self
        completion(.success(Void()))
    }

    public func stop(completion: @escaping (Result<Void, Error>) -> Void) {
        print("[UWB Native iOS] Invalidating NISession.")
        niSession?.invalidate()
        niSession = nil
        completion(.success(Void()))
    }

    public func startIosController(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        print("[UWB Native iOS] Generating discovery token.")
        guard let token = niSession?.discoveryToken else {
            let error = FlutterError(code: "UWB_ERROR", message: "Missing discovery token", details: nil)
            return completion(.failure(error))
        }
        guard let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            let error = FlutterError(code: "UWB_ERROR", message: "Failed to archive discovery token", details: nil)
            return completion(.failure(error))
        }
        completion(.success(FlutterStandardTypedData(bytes: tokenData)))
    }

    public func startIosAccessory(token: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        print("[UWB Native iOS] Starting accessory role with peer token.")
        guard let discoveryToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: token.data) else {
            let error = FlutterError(code: "UWB_ERROR", message: "Invalid discovery token data", details: nil)
            return completion(.failure(error))
        }
        let config = NINearbyPeerConfiguration(peerToken: discoveryToken)
        niSession?.run(config)
        completion(.success(Void()))
    }
    
    // These methods are Android-specific and should not be called on iOS.
    public func getAndroidAccessoryConfigurationData(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        completion(.failure(FlutterError(code: "WRONG_PLATFORM", message: "getAndroidAccessoryConfigurationData is for Android only", details: nil)))
    }

    public func initializeAndroidController(accessoryConfigurationData: FlutterStandardTypedData, sessionKeyInfo: FlutterStandardTypedData, sessionId: Int64, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
         completion(.failure(FlutterError(code: "WRONG_PLATFORM", message: "initializeAndroidController is for Android only", details: nil)))
    }

    public func startAndroidRanging(configData: FlutterStandardTypedData, isController: Bool, sessionKeyInfo: FlutterStandardTypedData, sessionId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(FlutterError(code: "WRONG_PLATFORM", message: "startAndroidRanging is for Android only", details: nil)))
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
        for object in nearbyObjects {
            var peerAddress = ""
            if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: object.discoveryToken, requiringSecureCoding: true) {
                peerAddress = tokenData.toHexString()
            }
            flutterApi?.onPeerLost(deviceName: "", peerAddress: peerAddress, completion: { _ in })
        }
    }
    
    public func sessionWasSuspended(_ session: NISession) {
        print("[UWB Native iOS] NI session was suspended.")
    }
    
    public func sessionSuspensionEnded(_ session: NISession) {
        print("[UWB Native iOS] NI session suspension ended.")
    }
    
    public func session(_ session: NISession, didInvalidateWith error: Error) {
        print("[UWB Native iOS] NI session did invalidate with error: \(error.localizedDescription)")
        flutterApi?.onRangingError(error: error.localizedDescription, completion: { _ in })
    }
    
    public func onReceived(data: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        print("[UWB Native iOS] Received data from Dart, likely a discovery token.")
        // This is where the handshake data (the peer's discovery token) is passed in from the Dart layer.
        startIosAccessory(token: data, completion: completion)
    }
}

extension Data {
    func toHexString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
