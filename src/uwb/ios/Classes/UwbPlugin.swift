import Flutter
import UIKit
import NearbyInteraction
import os

// This extension of Error is required to do use FlutterError in any Swift code.
extension FlutterError: Error {}

public class UwbPlugin: NSObject, FlutterPlugin, UwbHostApi, NISessionManagerDelegate {
    
    // MARK: - Properties
    
    static var flutterApi: UwbFlutterApi?
    private var niManager: NISessionManager
    private let logger = os.Logger(subsystem: "com.autheet.uwb", category: "UwbPlugin")
    
    // MARK: - Initializer
    
    override init() {
        self.niManager = NISessionManager()
        super.init()
        self.niManager.delegate = self
    }
     
    // MARK: - UwbHostApi Implementation
    
    // This method is not used on iOS for initializing ranging. 
    // The discovery token is generated on demand for peer-to-peer, 
    // and accessory configuration is received from the peer.
    func getLocalUwbAddress(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        let dummyData = FlutterStandardTypedData(bytes: Data())
        completion(.success(dummyData))
    }
    
    func startRanging(peerAddress: FlutterStandardTypedData, config: UwbSessionConfig, completion: @escaping (Result<Void, Error>) -> Void) {
        let peerId = String(config.sessionId)
        
        do {
            var niConfig: NIConfiguration?

            // Determine if this is an accessory (Android) or a peer (iOS)
            // A non-empty peerAddress indicates an accessory configuration from a FIRA-compliant device.
            if !peerAddress.data.isEmpty {
                logger.log("Received accessory configuration data. Creating NINearbyAccessoryConfiguration.")
                niConfig = try NINearbyAccessoryConfiguration(data: peerAddress.data)
            } else {
                // For iOS-to-iOS, we expect the sessionKeyInfo to contain the peer's discovery token.
                guard let tokenData = config.sessionKeyInfo?.data,
                      let discoveryToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: tokenData) else {
                    throw FlutterError(code: "UWB_ERROR", message: "Missing or invalid discovery token for peer configuration.", details: nil)
                }
                logger.log("Received peer discovery token. Creating NINearbyPeerConfiguration.")
                niConfig = NINearbyPeerConfiguration(peerToken: discoveryToken)
            }

            if let configuration = niConfig {
                 if #available(iOS 16.0, *) {
                    configuration.isCameraAssistanceEnabled = true
                }
                niManager.startRanging(peerId: peerId, configuration: configuration)
                completion(.success(()))
            } else {
                 throw FlutterError(code: "UWB_ERROR", message: "Could not create a valid NIConfiguration.", details: nil)
            }

        } catch {
            logger.error("Error starting ranging session for peer \(peerId): \(error.localizedDescription)")
            completion(.failure(error))
        }
    }
    
    func stopRanging(peerAddress: String, completion: @escaping (Result<Void, Error>) -> Void) {
        niManager.stopRanging(peerId: peerAddress)
        completion(.success(()))
    }
    
    func stopUwbSessions(completion: @escaping (Result<Void, Error>) -> Void) {
        niManager.invalidateAllSessions()
        completion(.success(()))
    }
       
    func isUwbSupported() throws -> Bool {
        return NISession.isSupported
    }

    // MARK: - NISessionManagerDelegate Implementation
    
    func sessionManager(didGenerateShareableConfigurationData data: Data, for peerId: String) {
        let flutterData = FlutterStandardTypedData(bytes: data)
        UwbPlugin.flutterApi?.onShareableConfigurationData(data: flutterData, peerId: peerId) { _ in }
    }
    
    func sessionManager(didUpdate rangingData: UwbData, for peerId: String) {
        let device = UwbDevice(id: peerId, name: "", uwbData: rangingData, deviceType: .accessory, state: .ranging)
        UwbPlugin.flutterApi?.onRanging(device: device) { _ in }
    }
    
    func sessionManager(didStart: Bool, for peerId: String) {
        let device = UwbDevice(id: peerId, name: "", uwbData: nil, deviceType: .accessory, state: .ranging)
        UwbPlugin.flutterApi?.onUwbSessionStarted(device: device) { _ in }
    }
    
    func sessionManager(didStop: Bool, for peerId: String) {
        let device = UwbDevice(id: peerId, name: "", uwbData: nil, deviceType: .accessory, state: .disconnected)
        UwbPlugin.flutterApi?.onUwbSessionDisconnected(device: device) { _ in }
    }

    func sessionManager(permissionRequired action: PermissionAction) {
        UwbPlugin.flutterApi?.onPermissionRequired(action: action) { _ in }
    }
    
    // MARK: - FlutterPlugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let api: UwbHostApi = UwbPlugin()
        UwbHostApiSetup.setUp(binaryMessenger: messenger, api: api)
        
        flutterApi = UwbFlutterApi(binaryMessenger: messenger)
    }
}
