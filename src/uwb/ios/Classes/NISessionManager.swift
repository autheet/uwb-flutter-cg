import Foundation
import NearbyInteraction
import Flutter // <-- FIX 1: Import Flutter to find FlutterError

// Assuming FlutterError is part of the Flutter framework.

class NISessionManager: NSObject, NISessionDelegate {
    // Use the peer's discovery token as the key for the session dictionary.
    private var sessions = [NIDiscoveryToken: NISession]()
    
    // MARK: - Public API

    /// Creates a temporary session to get the local device's discovery token.
    func getLocalDiscoveryToken() throws -> Data {
        let tempSession = NISession()
        tempSession.delegate = self // A delegate is required, even for a temporary session.
        
        guard let token = tempSession.discoveryToken else {
            // This can happen if the device doesn't support NI or permissions are missing.
            throw FlutterError(code: "NI_UNSUPPORTED", message: "Failed to get discovery token. Check device support and permissions.", details: nil)
        }
        
        // The temporary session is no longer needed and can be invalidated.
        // Note: The token remains valid until the app terminates.
        tempSession.invalidate()
        
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    /// Starts a ranging session with a peer or an accessory.
    func startRanging(with peerTokenData: Data, isAccessory: Bool) throws {
        let configuration: NIConfiguration
        var tokenForSessionKey: NIDiscoveryToken?

        if isAccessory {
            let accessoryConfiguration = try NINearbyAccessoryConfiguration(data: peerTokenData)
            configuration = accessoryConfiguration
            tokenForSessionKey = accessoryConfiguration.discoveryToken
        } else {
            guard let peerToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: peerTokenData) else {
                throw FlutterError(code: "TOKEN_ERROR", message: "Invalid peer discovery token data.", details: nil)
            }
            let peerConfiguration = NINearbyPeerConfiguration(peerToken: peerToken)
            configuration = peerConfiguration
            tokenForSessionKey = peerConfiguration.discoveryToken
        }
        
        // --- FIX 2: Use the extracted token for the dictionary key ---
        guard let discoveryToken = tokenForSessionKey else {
             throw FlutterError(code: "CONFIG_ERROR", message: "Could not get discovery token from configuration.", details: nil)
        }
        
        if let _ = sessions[discoveryToken] {
            print("Session with this token already running.")
            return
        }

        let newSession = NISession()
        newSession.delegate = self
        
        sessions[discoveryToken] = newSession
        newSession.run(configuration)
    }

    /// Stops a specific ranging session.
    func stopRanging(with peerTokenData: Data) {
        do {
            guard let peerToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: peerTokenData) else {
                print("Failed to unarchive token for stopping session. Data might be invalid.")
                return
            }
            
            if let session = sessions[peerToken] {
                session.invalidate()
                sessions.removeValue(forKey: peerToken)
                print("Session stopped for token: \(peerToken)")
            } else {
                print("No active session found for the given token to stop.")
            }
        } catch {
            print("Error stopping session: \(error.localizedDescription)")
        }
    }

    /// Stops all active ranging sessions.
    func stopAllSessions() {
        sessions.values.forEach { $0.invalidate() }
        sessions.removeAll()
        print("All NI sessions stopped.")
    }

    // MARK: - NISessionDelegate
    
    // Helper to get the discovery token from any configuration type
    private func getDiscoveryToken(from configuration: NIConfiguration?) -> NIDiscoveryToken? {
        if let config = configuration as? NINearbyPeerConfiguration {
            return config.peerDiscoveryToken
        }
        if let config = configuration as? NINearbyAccessoryConfiguration {
            return config.accessoryDiscoveryToken
        }
        return nil
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        // --- FIX 2 (continued): Use the helper to get the token ---
        guard let nearbyObject = nearbyObjects.first, let token = getDiscoveryToken(from: session.configuration) else { return }
        
        let rangingData = UwbRangingData(
            distance: nearbyObject.distance.map { Double($0) },
            azimuth: nearbyObject.direction.map { Double(atan2($0.x, $0.z)) },
            elevation: nearbyObject.direction.map {
                let horizontalDistance = sqrt($0.x * $0.x + $0.z * $0.z)
                return Double(atan2($0.y, horizontalDistance))
            }
        )
        
        guard let tokenData = token.archivedData else { return }
        let device = UwbDevice(address: tokenData, name: "", rangingData: rangingData)
        // --- FIX 3: Add missing argument labels ---
        UwbPlugin.flutterApi?.onRangingResult(device: device) { _ in }
    }
    
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard let token = getDiscoveryToken(from: session.configuration) else { return }
        
        var reasonString = "unknown"
        switch reason {
        case .peerEnded: reasonString = "peer ended"
        case .timeout: reasonString = "timeout"
        @unknown default: reasonString = "unknown"
        }
        print("Peer removed (\(reasonString)). Invalidating session.")

        guard let tokenData = token.archivedData else { return }
        let device = UwbDevice(address: tokenData, name: "", rangingData: nil)
        // --- FIX 3: Add missing argument labels ---
        UwbPlugin.flutterApi?.onPeerDisconnected(device: device) { _ in }
        
        session.invalidate()
        sessions.removeValue(forKey: token)
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        guard let token = getDiscoveryToken(from: session.configuration) else {
            print("A session invalidated with an error, but its token was missing.")
            UwbPlugin.flutterApi?.onRangingError(error: error as NSObject) { _ in }
            return
        }
        
        print("Session invalidated with error: \(error.localizedDescription)")
        // --- FIX 3: Add missing argument labels ---
        UwbPlugin.flutterApi?.onRangingError(error: error as NSObject) { _ in }
        
        sessions.removeValue(forKey: token)
    }
    
    func sessionWasSuspended(_ session: NISession) {
        print("Session was suspended.")
    }
    
    func sessionSuspensionEnded(_ session: NISession) {
        print("Session suspension ended.")
    }
}

// MARK: - Helper Extensions

extension NIDiscoveryToken {
    var archivedData: Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: true)
    }
}

// MARK: - Placeholder Structs for Compilation

struct UwbRangingData {
    let distance: Double?
    let azimuth: Double?
    let elevation: Double?
}

struct UwbDevice {
    let address: Data
    let name: String?
    let rangingData: UwbRangingData?
}

class UwbPlugin {
    static var flutterApi: FlutterApi? = FlutterApi()
}
class FlutterApi {
    func onRangingResult(device: UwbDevice, completion: @escaping (Result<Void, Error>) -> Void) {}
    func onPeerDisconnected(device: UwbDevice, completion: @escaping (Result<Void, Error>) -> Void) {}
    func onRangingError(error: NSObject, completion: @escaping (Result<Void, Error>) -> Void) {}
}
