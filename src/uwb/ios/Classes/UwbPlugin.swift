import Flutter
import UIKit
import NearbyInteraction
import os

// This extension of Error is required to do use FlutterError in any Swift code.
extension FlutterError: Error {}

public class UwbPlugin: NSObject, FlutterPlugin, UwbHostApi {
    
    // Host > Flutter
    static var flutterApi: UwbFlutterApi? = nil
    
    // Handles all NI Sessions
    private var niManager: NISessionManager = NISessionManager()
    
    private let logger = os.Logger(subsystem: "uwb_plugin", category: "UwbPlugin")
    
    override init() {
        super.init()
        self.niManager.permissionRequiredHandler = uwbPermissionRequired
        self.niManager.rangingDataCallback = onRangingResult
        self.niManager.uwbSessionStopped = uwbPeerDisconnected
    }
     
    // Flutter API
    func getLocalUwbAddress(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        let peer = Peer(id: "", name: "")
        let token = self.niManager.initPhoneSession(peer: peer)
        if (token != nil) {
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: token!, requiringSecureCoding: true)
                completion(.success(FlutterStandardTypedData(bytes: data)))
            } catch {
                completion(.failure(FlutterError(code: "uwb_error", message: "Failed to archive discovery token.", details: nil)))
            }
        } else {
            completion(.failure(FlutterError(code: "uwb_error", message: "Failed to get discovery token.", details: nil)))
        }
    }
    
    // Flutter API
    func startRanging(peerAddress: FlutterStandardTypedData, config: UwbSessionConfig) throws {
        do {
            let discoveryToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: peerAddress.data)
            self.niManager.startSessionWithPhone(peerId: String(data: peerAddress.data, encoding: .utf8)!, peerDiscoveryToken: discoveryToken!, config: config)
        } catch {
            throw FlutterError(code: "uwb_error", message: "Failed to unarchive discovery token.", details: nil)
        }
    }
    
    // Flutter API
    func stopRanging(peerAddress: String) throws {
        self.niManager.stopSession(peerId: peerAddress)
    }
    
    // Flutter API
    func stopUwbSessions() throws {
        self.niManager.stopSessions()
    }
       
    // Flutter API
    func isUwbSupported() throws -> Bool {
        return NISession.isSupported
    }
    
    // Flutter API
    func requestPermissions(completion: @escaping (Result<Bool, Error>) -> Void) {
        // On iOS, permissions are handled implicitly by the NISession.
        // If a permission is required, the `permissionRequiredHandler` will be called.
        // We can't know the result immediately, so we return true and let the handler deal with it.
        completion(.success(true))
    }

    // NI Session Manager delegate
    func uwbPermissionRequired(action: PermissionAction) {
        UwbPlugin.flutterApi?.onPermissionRequired(
            action: action,
            completion: {e in}
        )
    }
    
    // NI Session Manager delegate
    func onRangingResult(peerId: String, rangingData: UwbRangingData) {
        DispatchQueue.main.async {
            let device = UwbDevice(address: peerId.data(using: .utf8)!)
            UwbPlugin.flutterApi?.onRangingResult(device: device, rangingData: rangingData) { _ in }
        }
    }
    
    private func uwbPeerDisconnected(peerId: String) {
        DispatchQueue.main.async {
            let device = UwbDevice(address: peerId.data(using: .utf8)!)
            UwbPlugin.flutterApi?.onPeerDisconnected(device: device) { _ in }
        }
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger : FlutterBinaryMessenger = registrar.messenger()
        let api : UwbHostApi & NSObjectProtocol = UwbPlugin.init()
        UwbHostApiSetup.setUp(binaryMessenger: messenger, api: api)
        
        flutterApi = UwbFlutterApi(binaryMessenger: messenger)
    }
}