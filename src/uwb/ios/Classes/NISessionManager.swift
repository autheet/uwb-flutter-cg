import Foundation
import NearbyInteraction

class NISessionManager: NSObject, NISessionDelegate {
    private var sessions = [NIDiscoveryToken: NISession]()

    func getLocalDiscoveryToken() throws -> Data {
        // Create a temporary session to get a discovery token.
        let tempSession = NISession()
        guard let token = tempSession.discoveryToken else {
            throw FlutterError(code: "TOKEN_ERROR", message: "Failed to get discovery token.", details: nil)
        }
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    func startRanging(with peerTokenData: Data, config: UwbSessionConfig, isAccessory: Bool) throws {
        let configuration: NIConfiguration

        if isAccessory {
            guard let accessoryData = config.sessionKeyInfo else {
                throw FlutterError(code: "CONFIG_ERROR", message: "sessionKeyInfo is required for accessory mode", details: nil)
            }
            configuration = try NINearbyAccessoryConfiguration(data: accessoryData.data)
        } else {
            guard let peerToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: peerTokenData) else {
                throw FlutterError(code: "TOKEN_ERROR", message: "Invalid discovery token.", details: nil)
            }
            configuration = NINearbyPeerConfiguration(peerToken: peerToken)
        }

        let newSession = NISession()
        newSession.delegate = self
        sessions[configuration.discoveryToken] = newSession
        newSession.run(configuration)
    }

    func stopRanging(with peerTokenData: Data) {
        do {
            guard let peerToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: peerTokenData) else {
                return
            }
            sessions[peerToken]?.invalidate()
            sessions.removeValue(forKey: peerToken)
        } catch {
            // Handle error silently
        }
    }

    func stopAllSessions() {
        sessions.values.forEach { $0.invalidate() }
        sessions.removeAll()
    }

    // MARK: - NISessionDelegate

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let nearbyObject = nearbyObjects.first, let token = session.configuration?.discoveryToken else { return }
        
        let rangingData = UwbRangingData(
            distance: nearbyObject.distance.map { Double($0) },
            azimuth: nearbyObject.direction.map { Double(asin($0.x)) },
            elevation: nearbyObject.direction.map { Double(atan2($0.z, $0.y) + .pi / 2) }
        )
        // We don't know the name here, so we pass an empty string. The Dart layer will re-associate.
        let device = UwbDevice(address: token.archivedData, name: "", rangingData: rangingData)
        UwbPlugin.flutterApi?.onRangingResult(device) { _ in }
    }
    
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard let token = session.configuration?.discoveryToken else { return }
        let device = UwbDevice(address: token.archivedData, name: "", rangingData: nil)
        UwbPlugin.flutterApi?.onPeerDisconnected(device) { _ in }
        session.invalidate()
        sessions.removeValue(forKey: token)
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        guard let token = session.configuration?.discoveryToken else { return }
        UwbPlugin.flutterApi?.onRangingError(error.localizedDescription as NSObject) { _ in }
        sessions.removeValue(forKey: token)
    }
}

// Helper to get archived data from the token
extension NIDiscoveryToken {
    var archivedData: Data {
        return (try? NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: true)) ?? Data()
    }
}
