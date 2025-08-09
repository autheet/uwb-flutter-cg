import Foundation
import NearbyInteraction
import os
import Flutter

// MARK: - NISessionManagerDelegate Protocol
protocol NISessionManagerDelegate: AnyObject {
    func sessionManager(didUpdate rangingData: UwbData, for peerId: String)
    func sessionManager(didStart a: Bool, for peerId: String)
    func sessionManager(didStop a: Bool, for peerId: String)
    func sessionManager(permissionRequired action: PermissionAction)
}


class NISessionManager: NSObject, NISessionDelegate {
        
    // Callbacks to UwbPlugin
    weak var delegate: NISessionManagerDelegate?

    // Maps a peer's ID to their NI Session
    private var sessions = [String: NISession]()
    
    // Maps a peer's discovery token to their ID. This helps identify peers in didUpdate.
    private var peerTokenToId = [NIDiscoveryToken: String]()
    
    // Maps a session to a peer ID. This helps identify sessions in delegate callbacks.
    private var sessionToPeerId = [NISession: String]()
    
    private let logger = os.Logger(subsystem: "com.autheet.uwb", category: "NISessionManager")
  
    public func isDeviceRanging(deviceId: String) -> Bool {
        return sessions[deviceId] != nil
    }
    
    public func invalidateAllSessions() {
        for session in sessions.values {
            session.invalidate()
        }
        sessions.removeAll()
        peerTokenToId.removeAll()
        sessionToPeerId.removeAll()
        logger.log("All NI sessions invalidated.")
    }
    
    // This creates a temporary session to get the local discovery token.
    public func getLocalDiscoveryToken() throws -> NIDiscoveryToken {
        let tempSession = NISession()
        tempSession.delegate = self

        guard let token = tempSession.discoveryToken else {
            logger.error("Failed to get discovery token from temporary session.")
            throw FlutterError(code: "UWB_ERROR", message: "Could not get discovery token.", details: nil)
        }
        
        logger.log("Successfully retrieved local discovery token.")
        return token
    }
    
    public func startRanging(peerId: String, peerDiscoveryToken: NIDiscoveryToken) {
        if sessions[peerId] != nil {
            logger.warning("A session for peer \(peerId) already exists. Invalidating old one.")
            sessions[peerId]?.invalidate()
        }
        
        logger.log("Starting a new ranging session with peer: \(peerId)")
        
        let newSession = NISession()
        newSession.delegate = self
        
        sessions[peerId] = newSession
        peerTokenToId[peerDiscoveryToken] = peerId
        sessionToPeerId[newSession] = peerId
        
        let config = NINearbyPeerConfiguration(peerToken: peerDiscoveryToken)
        if #available(iOS 16.0, *) {
            // This can improve ranging accuracy when the devices are pointing at each other.
            config.isCameraAssistanceEnabled = true
        }
        
        newSession.run(config)
        logger.log("NI session for peer \(peerId) is now running.")
    }
    
    public func stopRanging(peerId: String) {
        guard let session = sessions[peerId] else {
            logger.error("No session found for peer \(peerId) to stop.")
            return
        }
        
        session.invalidate()
    }
    
    // MARK: - NISessionDelegate Methods
      
    internal func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let peerId = sessionToPeerId[session] else {
            logger.error("Received update for an unknown session.")
            return
        }

        guard let nearbyObject = nearbyObjects.first else {
            return
        }
        
        // Verify the object's token matches a known peer.
        guard peerTokenToId[nearbyObject.discoveryToken] == peerId else {
            logger.warning("Received update for peer \(peerId) but with an unknown discovery token.")
            return
        }
        
        var horizontalAngle: Float?
        if #available(iOS 16.0, *) {
            horizontalAngle = nearbyObject.horizontalAngle
        }
        
        var azimuth: Float = 0.0
        var elevation: Float = 0.0
        if let direction = nearbyObject.direction {
            azimuth = asin(direction.x)
            elevation = atan2(direction.z, direction.y) + .pi / 2
        }

        let direction3d = Direction3D(x: Double(nearbyObject.direction?.x ?? 0), y: Double(nearbyObject.direction?.y ?? 0), z: Double(nearbyObject.direction?.z ?? 0))
        let uwbData = UwbData(
            distance: nearbyObject.distance.map { Double($0) },
            azimuth: Double(azimuth * 180 / .pi),
            elevation: Double(elevation * 180 / .pi),
            direction: direction3d,
            horizontalAngle: horizontalAngle.map { Double($0) }
        )

        delegate?.sessionManager(didUpdate: uwbData, for: peerId)
    }
    
    internal func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard let peerId = sessionToPeerId[session] else {
            logger.error("didRemove called for an unknown session.")
            return
        }
        
        switch reason {
            case .peerEnded:
                logger.log("Peer \(peerId) ended the session.")
            case .timeout:
                logger.log("Session with peer \(peerId) timed out.")
            default:
                logger.log("Session with peer \(peerId) removed for unknown reason: \(reason.rawValue)")
        }

        delegate?.sessionManager(didStop: true, for: peerId)
        stopRanging(peerId: peerId)
    }
    
    internal func sessionWasSuspended(_ session: NISession) {
        guard let peerId = sessionToPeerId[session] else { return }
        logger.warning("Session for peer \(peerId) was suspended.")
    }

    internal func sessionSuspensionEnded(_ session: NISession) {
        guard let peerId = sessionToPeerId[session] else { return }
        logger.log("Session suspension ended for peer \(peerId). Attempting to rerun.")
        if let config = session.configuration {
            session.run(config)
        } else {
            logger.error("Could not rerun session for \(peerId) because configuration was nil.")
            delegate?.sessionManager(didStop: true, for: peerId)
            stopRanging(peerId: peerId)
        }
    }
    
    internal func session(_ session: NISession, didInvalidateWith error: Error) {
        guard let peerId = sessionToPeerId[session] else {
            logger.error("An unknown session was invalidated. Error: \(error.localizedDescription)")
            return
        }

        logger.error("Session for peer \(peerId) invalidated with error: \(error.localizedDescription)")
        
        if let niError = error as? NIError {
            switch niError.code {
            case .userDidNotAllow:
                delegate?.sessionManager(permissionRequired: .request)
            case .activeSessionsLimitExceeded:
                logger.error("Maximum number of active NI sessions exceeded.")
                delegate?.sessionManager(didStop: true, for: peerId)
            default:
                delegate?.sessionManager(didStop: true, for: peerId)
            }
        } else {
            delegate?.sessionManager(didStop: true, for: peerId)
        }
        
        if let tokenToRemove = peerTokenToId.first(where: { $1 == peerId })?.key {
            peerTokenToId.removeValue(forKey: tokenToRemove)
        }
        sessionToPeerId.removeValue(forKey: session)
        sessions.removeValue(forKey: peerId)
    }
    
    func sessionDidStartRunning(_ session: NISession) {
         guard let peerId = sessionToPeerId[session] else {
            logger.error("sessionDidStartRunning called for an unknown session.")
            return
        }
        logger.log("Successfully started session with peer \(peerId).")
        delegate?.sessionManager(didStart: true, for: peerId)
    }
}
