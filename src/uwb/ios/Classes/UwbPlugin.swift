import Flutter
import UIKit
import NearbyInteraction
import os

extension FlutterError: Error {}

public class UwbPlugin: NSObject, FlutterPlugin, UwbHostApi {
    
    static var flutterApi: UwbFlutterApi?
    private var niSession: NISession?
    private let logger = os.Logger(subsystem: "com.autheet.uwb", category: "UwbPlugin")
    
    public func start(deviceName: String, serviceUUIDDigest: String, completion: @escaping (Result<Void, Error>) -> Void) {
        if niSession == nil {
            niSession = NISession()
            niSession?.delegate = self
        }
        completion(.success(()))
    }

    public func stop(completion: @escaping (Result<Void, Error>) -> Void) {
        niSession?.invalidate()
        niSession = nil
        completion(.success(()))
    }

    public func startIosController(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        guard let session = niSession, let token = session.discoveryToken else {
            completion(.failure(FlutterError(code: "UWB_ERROR", message: "Failed to get discovery token.", details: nil)))
            return
        }

        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            completion(.success(FlutterStandardTypedData(bytes: data)))
        } catch {
            completion(.failure(FlutterError(code: "UWB_ERROR", message: "Failed to archive discovery token.", details: error.localizedDescription)))
        }
    }
    
    public func startIosAccessory(token: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let session = niSession else {
            completion(.failure(FlutterError(code: "UWB_ERROR", message: "NISession not initialized.", details: nil)))
            return
        }

        do {
            guard let discoveryToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: token.data) else {
                throw FlutterError(code: "UWB_ERROR", message: "Invalid discovery token data.", details: nil)
            }
            let config = NINearbyPeerConfiguration(peerToken: discoveryToken)
            session.run(config)
            completion(.success(()))
        } catch {
            completion(.failure(FlutterError(code: "UWB_ERROR", message: "Failed to start accessory ranging.", details: error.localizedDescription)))
        }
    }

    // --- Android Placeholders ---
    public func getAndroidAccessoryConfigurationData(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        completion(.failure(FlutterError(code: "UNSUPPORTED", message: "This method is for Android only.", details: nil)))
    }
    
    public func initializeAndroidController(accessoryConfigurationData: FlutterStandardTypedData, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        completion(.failure(FlutterError(code: "UNSUPPORTED", message: "This method is for Android only.", details: nil)))
    }
    
    public func startAndroidRanging(configData: FlutterStandardTypedData, isController: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(FlutterError(code: "UNSUPPORTED", message: "This method is for Android only.", details: nil)))
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let api: UwbHostApi = UwbPlugin()
        UwbHostApi.setUp(binaryMessenger: messenger, api: api)
        flutterApi = UwbFlutterApi(binaryMessenger: messenger)
    }
}

extension UwbPlugin: NISessionDelegate {
    public func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let nearbyObject = nearbyObjects.first else { return }
        
        // Extract both azimuth (x) and elevation (y) from the direction vector.
        let azimuth = nearbyObject.direction.map { Double($0.x) }
        let elevation = nearbyObject.direction.map { Double($0.y) }
        
        let result = RangingResult(
            peerAddress: nearbyObject.discoveryToken.description, 
            deviceName: "", // Device name is now handled exclusively in the Dart layer.
            distance: nearbyObject.distance, 
            azimuth: azimuth,
            elevation: elevation
        )
        
        UwbPlugin.flutterApi?.onRangingResult(result: result) { _ in }
    }
    
    public func session(_ session: NISession, didInvalidateWith error: Error) {
        UwbPlugin.flutterApi?.onRangingError(error: error.localizedDescription) { _ in }
    }
}
