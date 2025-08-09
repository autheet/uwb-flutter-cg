import Flutter
import UIKit
import NearbyInteraction
import os

// This extension of Error is required to do use FlutterError in any Swift code.
extension FlutterError: Error {}

public class UwbPlugin: NSObject, FlutterPlugin, UwbHostApi {
    
    // Host > Flutter
    static var flutterApi: UwbFlutterApi? = nil
    
    // Event Channels Data Handler
    static var uwbDataHandler: UwbDataHandler? = nil
        
    // Handles all NI Sessions
    private var niManager: NISessionManager = NISessionManager()
    
    private let logger = os.Logger(subsystem: "uwb_plugin", category: "UwbPlugin")
    
    override init() {
        super.init()
        self.niManager.permissionRequiredHandler = uwbPermissionRequired
        self.niManager.uwbSessionStarted = uwbSessionStarted
        self.niManager.uwbSessionStopped = uwbPeerDisconnected
    }
     
    // Flutter API
    func getLocalUwbAddress(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        // On iOS, the discovery token serves the same purpose as the UWB address on Android.
        let token = self.niManager.initPhoneSession()
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
    func startRanging(peerAddress: FlutterStandardTypedData, config: UwbSessionConfig, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let discoveryToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: peerAddress.data)
            self.niManager.startSessionWithPhone(peerId: String(data: peerAddress.data, encoding: .utf8)!, peerDiscoveryToken: discoveryToken!, config: config)
        } catch {
            completion(.failure(error))
        }
        completion(.success(()))
    }
    
    // Flutter API
    func stopRanging(peerAddress: String, completion: @escaping (Result<Void, Error>) -> Void) {
        self.niManager.stopSession(peerId: peerAddress)
        completion(.success(()))
    }
    
    // Flutter API
    func stopUwbSessions(completion: @escaping (Result<Void, Error>) -> Void) {
        self.niManager.stopSessions()
        completion(.success(()))
    }
       
    // Flutter API
    func isUwbSupported() throws -> Bool {
        return NISession.isSupported
    }

    // NI Session Manager delegate
    func uwbPermissionRequired(action: PermissionAction) {
        UwbPlugin.flutterApi?.onPermissionRequired(
            action: action,
            completion: {e in}
        )
    }
    
    // NI Session Manager delegate
    func uwbSessionStarted(peerId: String) {
        DispatchQueue.main.async {
            let device = UwbDevice(id: peerId, name: peerId, uwbData: nil, deviceType: .smartphone, state: .ranging)
            UwbPlugin.flutterApi?.onUwbSessionStarted(
                device: device,
                completion: {e in}
            )
        }
    }
    
    private func uwbPeerDisconnected(peerId: String, type: DeviceType) {
        DispatchQueue.main.async {
            let device = UwbDevice(id: peerId, name: peerId, uwbData: nil, deviceType: type, state: .disconnected)
            UwbPlugin.flutterApi?.onUwbSessionDisconnected(
                device: device,
                completion: {e in}
            )
        }
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger : FlutterBinaryMessenger = registrar.messenger()
        let api : UwbHostApi & NSObjectProtocol = UwbPlugin.init()
        UwbHostApi.setUp(binaryMessenger: messenger, api: api)
        
        // Initialize all event channels
        let uwbDataChannel = FlutterEventChannel(name: "uwb_plugin/uwbData", binaryMessenger: messenger)
        uwbDataHandler = UwbDataHandler()
        uwbDataChannel.setStreamHandler(uwbDataHandler)
        
        flutterApi = UwbFlutterApi(binaryMessenger: messenger)
    }
}
