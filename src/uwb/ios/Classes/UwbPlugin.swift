
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
        // With the reactive approach, we no longer need to check for permission here.
        // We simply create the session, and if permissions are not determined,
        // the OS will prompt the user. If they are denied, the delegate
        // method session(_:didInvalidateWith:) will be called.
        NSLog("[UWB Native iOS] Initializing NISession.")
        niSession = NISession()
        niSession?.delegate = self
    }

    public func stop() async throws {
        NSLog("[UWB Native iOS] Invalidating NISession.")
        niSession?.invalidate()
        niSession = nil
    }

    // MARK: - FiRa / App-to-App Ranging

    public func generateControllerConfig(accessoryAddress: FlutterStandardTypedData, sessionKeyInfo: FlutterStandardTypedData, sessionId: Int64) async throws -> UwbConfig {
        NSLog("[UWB Native iOS] Generating FiRa configuration for accessory.")
        guard let token = niSession?.discoveryToken else {
            throw PigeonError(code: "UWB_ERROR", message: "Missing discovery token for Controller role", details: nil)
        }
        
        // For iOS 18+, we should ideally use the new NIAppToAppDevice API,
        // but NINearbyAccessoryConfiguration remains for FiRa compliance.
        let accessoryData = accessoryAddress.data
        let config = try NINearbyAccessoryConfiguration(data: accessoryData)
        
        niSession?.run(config)
        
        let uwbConfig = UwbConfig(
            uwbConfigId: 1, // CONFIG_UNICAST_DS_TWR
            sessionId: sessionId,
            sessionKeyInfo: sessionKeyInfo,
            channel: 9,
            preambleIndex: 10,
            peerAddress: try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true).toFlutterStandardTypedData()
        )
        return uwbConfig
    }
    
    // ... Other UwbHostApi methods remain the same ...
    public func startIosController() async throws -> FlutterStandardTypedData {
        // This is for legacy Apple-to-Apple communication
        guard let token = niSession?.discoveryToken else { throw PigeonError(code: "UWB_ERROR", message: "Missing discovery token", details: nil) }
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true).toFlutterStandardTypedData()
    }
    public func startIosAccessory(token: FlutterStandardTypedData) async throws {
        guard let discoveryToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: token.data) else {
            throw PigeonError(code: "UWB_ERROR", message: "Invalid discovery token", details: nil)
        }
        let config = NINearbyPeerConfiguration(peerToken: discoveryToken)
        niSession?.run(config)
    }
    public func getAccessoryAddress() async throws -> FlutterStandardTypedData {
        guard let token = niSession?.discoveryToken else { throw PigeonError(code: "UWB_ERROR", message: "Missing discovery token", details: nil) }
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true).toFlutterStandardTypedData()
    }
    public func startAccessoryRanging(config: UwbConfig) async throws {
         NSLog("[UWB Native iOS] Accessory ranging started (via config).")
    }

    // MARK: - NISessionDelegate Methods
    
    public func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        for object in nearbyObjects {
            var peerAddress = ""
            if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: object.discoveryToken, requiringSecureCoding: true) {
                peerAddress = tokenData.toHexString()
            }
            let result = RangingResult(
                peerAddress: peerAddress,
                deviceName: "",
                distance: object.distance.map { Double($0) },
                azimuth: object.direction.map { Double($0.x) },
                elevation: object.direction.map { Double($0.y) }
            )
            flutterApi?.onRangingResult(result: result, completion: { _ in })
        }
    }

    public func session(_ session: NISession, didInvalidateWith error: Error) {
        NSLog("[UWB Native iOS] Session did invalidate with error: %@", error.localizedDescription)

        // --- REACTIVE PERMISSION HANDLING ---
        // Check if the error is specifically because the user denied permission.
        if let niError = error as? NIError, niError.code == .userDidNotAllow {
            // Show a native alert to guide the user to the Settings app.
            showSettingsAlert()
            
            // Send a specific error code back to Dart so the UI can react appropriately.
            flutterApi?.onRangingError(error: "PERMISSION_DENIED", completion: { _ in })
        } else {
            // For all other errors, send the localized description.
            flutterApi?.onRangingError(error: error.localizedDescription, completion: { _ in })
        }
    }

    // ... Other delegate stubs remain the same ...
    public func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {}
    public func sessionWasSuspended(_ session: NISession) { NSLog("[UWB Native iOS] NI session was suspended.") }
    public func sessionSuspensionEnded(_ session: NISession) { NSLog("[UWB Native iOS] NI session suspension ended.") }

    // MARK: - Helper Functions
    
    @MainActor
    private func showSettingsAlert() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }

        let accessAlert = UIAlertController(title: "Nearby Interactions Required",
                                             message: "This app uses Nearby Interactions to find and measure distance. Please enable this permission in Settings.",
                                             preferredStyle: .alert)
        accessAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        accessAlert.addAction(UIAlertAction(title: "Go to Settings", style: .default, handler: { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
            }
        }))
        
        // Find the most appropriate view controller to present the alert on.
        var presenter = rootViewController
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(accessAlert, animated: true, completion: nil)
    }
}
