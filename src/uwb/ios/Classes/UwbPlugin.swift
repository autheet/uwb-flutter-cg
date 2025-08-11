import Flutter
import UIKit
import NearbyInteraction
import os

// This extension of Error is required to do use FlutterError in any Swift code.
extension FlutterError: Error {}

public class UwbPlugin: NSObject, FlutterPlugin, UwbHostApi, NISessionDelegate {
    
    // MARK: - Properties
    
    static var flutterApi: UwbFlutterApi?
    private var niSession: NISession?
    private let logger = os.Logger(subsystem: "com.autheet.uwb", category: "UwbPlugin")
    
    // MARK: - UwbHostApi Implementation
    
    func isSupported(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(NISession.isSupported))
    }
    
    func getLocalEndpoint(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        // Always create a new session for the local endpoint, as the session may not have started yet.
        let session = NISession()
        session.delegate = self
        self.niSession = session
        
        guard let token = session.discoveryToken else {
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
    
    func startRanging(peerEndpoint: FlutterStandardTypedData, isController: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: peerEndpoint.data) else {
                throw FlutterError(code: "UWB_ERROR", message: "Invalid peer endpoint data.", details: nil)
            }
            let config = NINearbyPeerConfiguration(peerToken: token)
            niSession?.run(config)
            completion(.success(()))
        } catch {
            completion(.failure(FlutterError(code: "UWB_ERROR", message: "Failed to start ranging.", details: error.localizedDescription)))
        }
    }
    
    func stopRanging(completion: @escaping (Result<Void, Error>) -> Void) {
        niSession?.invalidate()
        niSession = nil
        completion(.success(()))
    }
    
    func closeSession(completion: @escaping (Result<Void, Error>) -> Void) {
        niSession?.invalidate()
        niSession = nil
        completion(.success(()))
    }
    
    // MARK: - NISessionDelegate Implementation
    
    public func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let nearbyObject = nearbyObjects.first else { return }
        
        let rangingData = UwbRangingData(
            distance: nearbyObject.distance,
            azimuth: nearbyObject.direction?.x,
            elevation: nearbyObject.direction?.y
        )
        let device = UwbRangingDevice(
            id: nearbyObject.discoveryToken.description,
            state: .ranging,
            data: rangingData
        )
        UwbPlugin.flutterApi?.onRangingResult(device: device) { _ in }
    }
    
    public func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard let nearbyObject = nearbyObjects.first else { return }
        
        let device = UwbRangingDevice(
            id: nearbyObject.discoveryToken.description,
            state: .lost,
            data: nil
        )
        UwbPlugin.flutterApi?.onRangingResult(device: device) { _ in }
    }
    
    public func session(_ session: NISession, didInvalidateWith error: Error) {
        UwbPlugin.flutterApi?.onRangingError(error: error.localizedDescription) { _ in }
    }

    public func session(_ session: NISession, didGenerateShareableConfigurationData data: Data, for object: NINearbyObject) {
         // This is not directly used in our new architecture, as the token exchange happens before ranging starts.
         // However, we can use this to send updated configuration data if needed.
        let peerId = object.discoveryToken.description
        UwbPlugin.flutterApi?.onShareableConfigurationData(data: FlutterStandardTypedData(bytes: data), peerId: peerId) { _ in }
    }
    
    // MARK: - FlutterPlugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let api: UwbHostApi = UwbPlugin()
        UwbHostApi.setUp(binaryMessenger: messenger, api: api)
        
        flutterApi = UwbFlutterApi(binaryMessenger: messenger)
    }
}
