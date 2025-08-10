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
    
    func getLocalUwbAddress(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        // This is not used on iOS, but we need to return something.
        // On iOS, the discovery token is generated and shared out-of-band.
        completion(.success(FlutterStandardTypedData(bytes: Data())))
    }
    
    func startRanging(peerAddress: FlutterStandardTypedData, config: UwbSessionConfig) throws {
        let peerId = String(config.sessionId)
        
        var niConfig: NIConfiguration

        if !peerAddress.data.isEmpty {
            logger.log("Creating NINearbyAccessoryConfiguration.")
            niConfig = try NINearbyAccessoryConfiguration(data: peerAddress.data)
        } else {
            guard let tokenData = config.sessionKeyInfo?.data,
                  let discoveryToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: tokenData) else {
                throw FlutterError(code: "UWB_ERROR", message: "Missing or invalid discovery token for peer configuration.", details: nil)
            }
            logger.log("Creating NINearbyPeerConfiguration.")
            niConfig = NINearbyPeerConfiguration(peerToken: discoveryToken)
        }

        if #available(iOS 16.0, *) {
            niConfig.isCameraAssistanceEnabled = true
        }

        niManager.startRanging(peerId: peerId, configuration: niConfig)
    }
    
    func stopRanging(peerAddress: String) throws {
        niManager.stopRanging(peerId: peerAddress)
    }
    
    func stopUwbSessions() throws {
        niManager.invalidateAllSessions()
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
