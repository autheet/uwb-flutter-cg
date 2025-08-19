import Flutter
import UIKit
import NearbyInteraction
import Foundation
import MultipeerConnectivity
import os

// This extension of Error is required to do use FlutterError in any Swift code.
extension FlutterError: Error {}

public class UwbPlugin: NSObject, FlutterPlugin, UwbHostApi, NISessionDelegate {
    
    // Host > Flutter
    static var flutterApi: UwbFlutterApi? = nil
    
    private var appName: String? = nil
    private var serviceId: String? = nil
    private var identityId: String? = nil
    private var deviceName: String? = nil
    
    private var isDiscovering = false
    
    // Bluetooth Accessory Discovery Service
    private var bluetoothManager = BluetoothManager()
    
    // iPhone to iPhone Discovery Service
    private var mpcManager: MultipeerConnectivityManager? = nil
    
    private let logger = os.Logger(subsystem: "uwb_plugin", category: "UwbPlugin")
    
    private var pendingInvitations : [String] = []
    
    override init() {
        super.init()
        self.bluetoothManager.accessoryDiscoveryHandler = accessoryFound
        self.bluetoothManager.accessoryConnectedHandler = accessoryConnected
        self.bluetoothManager.accessoryDisconnectedHandler = accessoryDisconnected
        self.bluetoothManager.accessoryDataHandler = accessorySharedData
        self.bluetoothManager.accessoryLostHandler = accessoryLost
        
        self.niManager.permissionRequiredHandler = uwbPermissionRequired
        self.serviceId = convertToValidServiceId(serviceId: appName!)
        self.identityId = "app.\(appName!)"
    }
    
    private func initMpcSession(deviceName: String, serviceId: String, identityId: String) {
        self.mpcManager = MultipeerConnectivityManager(
            localPeerId: deviceName,
            service: serviceId,
            identity: identityId
        )
        self.mpcManager?.peerConnectedHandler = mpcPeerConnected
        self.mpcManager?.peerFoundHandler = mpcPeerFound
        self.mpcManager?.peerLostHandler = mpcPeerLost
        self.mpcManager?.peerInvitedHandler = mpcPeerInvited
    }
     

    // Send peer instead of uwb Device
    func accessoryFound(peer: Peer) {
        UwbPlugin.flutterApi?.onHostDiscoveryDeviceFound(
            device: UwbDevice(
                id: peer.id,
                name: peer.name,
                deviceType: DeviceType.accessory,
                state: DeviceState.found
            ),
            completion: {e in}
        )
    }
    
    // Callback Bluetooth Manager
    func accessoryLost(peer: Peer) {
        UwbPlugin.flutterApi?.onHostDiscoveryDeviceLost(
            device: UwbDevice(
                id: peer.id,
                name: peer.name,
                deviceType: DeviceType.accessory,
                state: DeviceState.lost
            ),
            completion: {e in}
        )
    }
    
    // Callback Bluetooth Manager
    func accessoryConnected(peer: Peer) {
        UwbPlugin.flutterApi?.onHostDiscoveryDeviceConnected(
            device: UwbDevice(
                id: peer.id,
                name: peer.name,
                deviceType: DeviceType.smartphone,
                state: DeviceState.connected
            ),
            completion: {e in}
        )
        
    }
    
    // Callback Bluetooth Manager
    func accessoryDisconnected(peer: Peer) {
        logger.log("Accessory Disconnected: \(peer.name)")
        UwbPlugin.flutterApi?.onHostDiscoveryDeviceDisconnected(
            device: UwbDevice(
                id: peer.id,
                name: peer.name,
                deviceType: DeviceType.accessory,
                state: DeviceState.disconnected
            ),
            completion: {e in}
        )
    }
    
    // Callback Bluetooth Manager
    private func accessorySharedData(data: Data, peer: Peer) {} // This will be handled in Flutter now
    
    // Flutter API
    func discoverDevices(deviceName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        isDiscovering = true
        // TODO: assert device name
        
        // check if its a new name if so create a new mc session
        if (self.deviceName != deviceName || self.mpcManager == nil) {
            self.deviceName = deviceName
            
            // invalidate previous session
            self.mpcManager?.invalidate()
            
            initMpcSession(deviceName: deviceName, serviceId: self.serviceId!, identityId: self.identityId!)
        }
        self.mpcManager?.startDiscovery()
        self.bluetoothManager.start()
        completion(.success(()))
    }
    
    // Flutter API
    func stopDiscovery(completion: @escaping (Result<Void, Error>) -> Void) {
        self.isDiscovering = false
        self.mpcManager?.stopDiscovery()
        self.mpcManager?.stopAdvertising()
        self.bluetoothManager.stop()
        completion(.success(()))
    }
    
   // Flutter API
    func handleConnectionRequest(device: UwbDevice, accept: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try self.mpcManager?.handleInvitation(peerId: device.id, accept: accept)
        } catch let error  {
            completion(.failure(FlutterError(code: "UWB_ERROR", message: error.localizedDescription, details: nil)))
        }
        completion(.success(()))
    }
    
    // Flutter API - Start Ranging with UwbConfig
    public func startRanging(config: UwbConfig, completion: @escaping (Result<Void, Error>) -> Void) {
        niSession = NISession()
        niSession?.delegate = self
        
        do {
            let niConfig = try NINearbyAccessoryConfiguration(data: config.peerAddress.data) // Assuming peerAddress contains the accessory data
            niSession?.run(niConfig)
            completion(.success(()))
        } catch {
            completion(.failure(FlutterError(code: "UWB_ERROR", message: "Failed to create NINearbyAccessoryConfiguration: \(error.localizedDescription)", details: nil)))
        }
    // Flutter API
    func startRanging(device: UwbDevice, completion: @escaping (Result<Void, Error>) -> Void) {
        if (device.deviceType == DeviceType.smartphone) {
            connectWithPhone(device: device)
        } else {
            connectWithAccessory(device: device)
        }
        
    }
    
    // Flutter API
    func stopRanging(device: UwbDevice, completion: @escaping (Result<Void, Error>) -> Void) {
        if (device.deviceType == DeviceType.smartphone) {
            self.mpcManager?.disconnectFromPeer(peerId: device.id)
        } else {
            self.bluetoothManager.disconnectPeripheral(deviceId: device.id)
            do {
                try self.bluetoothManager.sendData(data: Data([MessageId.stop.rawValue]), deviceId: device.id)
                try self.bluetoothManager.sendData(data: Data([MessageId.initialize.rawValue]), deviceId: device.id)
            } catch {
                logger.error("Failed to send data to accessory: \(error)")
            }
        }
        self.niManager.stopSession(peerId: device.id)
        completion(.success(()))
    }
    
    // Flutter API
    func stopUwbSessions(completion: @escaping (Result<Void, Error>) -> Void) {
        self.niManager.stopSessions()
        completion(.success(()))
    }
       
    // Flutter API
    public func isUwbSupported(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(NISession.isSupported))
    }

    // NI Session Manager delegate
    func uwbPermissionRequired(action: PermissionAction) {
    }
    
    // NI Session Manager delegate
    func uwbSessionStarted(peerId: String) {
    }
    
    // MultipeerConnectivity delegate
    private func uwbPeerDisconnected(peerId: String, type: DeviceType) {} // Handled in Flutter

    private func convertToValidServiceId(serviceId: String) -> String {
        // cap string to max 15 characters
        let cappedServiceId = String(serviceId.prefix(15))

        // remove underscores or dashes
        let validServiceId = cappedServiceId.replacingOccurrences(of: "_", with: "")
                                            .replacingOccurrences(of: "-", with: "")
        
        return validServiceId
    }

    // Handles all NI Sessions
    private var niManager: NISessionManager = NISessionManager() // Keep NI Session Management
    
    // NI Session Delegate
    public func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        for object in nearbyObjects {
            let uwbData = UwbData(
                distance: object.distance.map { Double($0) },
                azimuth: object.direction.map { Double($0.x) }, // Assuming x maps to azimuth
                elevation: object.direction.map { Double($0.y) }, // Assuming y maps to elevation
                direction: object.direction.map { Direction3D(x: Double($0.x), y: Double($0.y), z: Double($0.z)) },
                horizontalAngle: object.horizontalAngle.map { Double($0) }
            )
            UwbPlugin.flutterApi?.onUwbRangingResult(data: uwbData, completion: { _ in })
        }
    }

    // NI Session Delegate
    public func session(_ session: NISession, didInvalidateWith error: Error) {
        NSLog("[UWB Native iOS] Session did invalidate with error: %@", error.localizedDescription)
        
        // --- REACTIVE PERMISSION HANDLING ---
        // Check if the error is specifically because the user denied permission.
        if let niError = error as? NIError, niError.code == .userDidNotAllow {
            // Show a native alert to guide the user to the Settings app.
            showSettingsAlert()
            
            // Send a specific error code back to Dart so the UI can react appropriately.
            UwbPlugin.flutterApi?.onUwbRangingError(error: "PERMISSION_DENIED", completion: { _ in })
        } else {
            // For all other errors, send the localized description.
            UwbPlugin.flutterApi?.onUwbRangingError(error: error.localizedDescription, completion: { _ in })
        }
    }

    // NI Session Delegate Stubs
    public func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {}
    public func sessionWasSuspended(_ session: NISession) { NSLog("[UWB Native iOS] NI session was suspended.") }
    public func sessionSuspensionEnded(_ session: NISession) { NSLog("[UWB Native iOS] NI session suspension ended.") }

    // MultipeerConnectivity delegate
    private func mpcPeerFound(peerId: String) {
        DispatchQueue.main.async {
            UwbPlugin.flutterApi?.onHostDiscoveryDeviceFound(
                device:  UwbDevice(
                    id: peerId,
                    name: peerId,
                    deviceType: DeviceType.smartphone,
                    state: DeviceState.found
                ),
                completion: {e in}
            )
        }
    }
    
    private func mpcPeerInvited(peerId: String) {
        DispatchQueue.main.async {
            UwbPlugin.flutterApi?.onHostDiscoveryConnectionRequestReceived(
                device: UwbDevice(
                    id: peerId,
                    name: peerId,
                    deviceType: DeviceType.smartphone,
                    state: DeviceState.pending
                ),
                completion: {e in}
            )
        }
    }
       
    // MultipeerConnectivity delegate
    private func mpcPeerLost(peerId: String) {
        DispatchQueue.main.async {
            UwbPlugin.flutterApi?.onHostDiscoveryDeviceLost(
                device: UwbDevice(
                    id: peerId,
                    name: peerId,
                    deviceType: DeviceType.smartphone,
                    state: DeviceState.lost
                ),
                completion: {e in}
            )
        }
    }
   
    // MultipeerConnectivity delegate
    private func mpcPeerDisconnected(peerId: String) {
        // There is no rejected event by MPC, so check if we have some pending invations
        if let index = pendingInvitations.firstIndex(of: peerId) {
            pendingInvitations.remove(at: index)
            
            DispatchQueue.main.async {
                UwbPlugin.flutterApi?.onHostDiscoveryDeviceRejected(
                    device: UwbDevice(
                        id: peerId,
                        name: peerId,
                        deviceType: DeviceType.smartphone,
                        state: DeviceState.rejected
                    ),
                    completion: {e in}
                )
            }
        } else {
            // Force to stop UWB Session, so we don't have to wait for UWB Timeout.
            if (self.niManager.isDeviceRanging(deviceId: peerId)) {
                self.niManager.stopSession(peerId: peerId)
                self.uwbPeerDisconnected(peerId: peerId, type: DeviceType.smartphone)
                if (isDiscovering) {
                    self.mpcManager?.restartDiscovery()
                }
            }
            
            DispatchQueue.main.async {
                UwbPlugin.flutterApi?.onHostDiscoveryDeviceDisconnected(
                    device: UwbDevice(
                        id: peerId,
                        name: peerId,
                        deviceType: DeviceType.smartphone,
                        state: DeviceState.disconnected
                    ),
                    completion: {e in}
                )
            }
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger : FlutterBinaryMessenger = registrar.messenger()
        let api : UwbHostApi & NSObjectProtocol = UwbPlugin.init()
        UwbHostApiSetup.setUp(binaryMessenger: messenger, api: api)
        
        // Initialize all event channels
        let uwbDataChannel = FlutterEventChannel(name: "uwb_plugin/uwbData", binaryMessenger: messenger)
        flutterApi = UwbFlutterApi(binaryMessenger: messenger)
    }
}
