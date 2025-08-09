import Foundation
import NearbyInteraction
import os

// MARK: - Custom Native Error
enum NISessionManagerError: Error {
    case configurationCreationError(String)
    case invalidConfiguration
}


// MARK: - NISessionManagerDelegate Protocol
protocol NISessionManagerDelegate: AnyObject {
    func sessionManager(didGenerateShareableConfigurationData data: Data, for peerId: String)
    func sessionManager(didUpdate rangingData: UwbData, for peerId: String)
    func sessionManager(didStart a: Bool, for peerId: String)
    func sessionManager(didStop a: Bool, for peerId: String)
    func sessionManager(permissionRequired action: PermissionAction)
}

class NISessionManager: NSObject, NISessionDelegate {
        
    weak var delegate: NISessionManagerDelegate?

    private var sessions = [String: NISession]()
    private var peerTokenToId = [NIDiscoveryToken: String]()
    private var sessionToPeerId = [NISession: String]()
    
    private let logger = os.Logger(subsystem: "com.autheet.uwb", category: "NISessionManager")
  
    public func invalidateAllSessions() {
        for session in sessions.values {
            session.invalidate()
        }
        sessions.removeAll()
        peerTokenToId.removeAll()
        sessionToPeerId.removeAll()
        logger.log("All NI sessions invalidated.")
    }
    
    public func startRanging(peerId: String, configuration: NIConfiguration) {
        if sessions[peerId] != nil {
            logger.warning("A session for peer \(peerId) already exists. Invalidating old one.")
            sessions[peerId]?.invalidate()
        }
        
        logger.log("Starting a new ranging session with peer: \(peerId)")
        
        let newSession = NISession()
        newSession.delegate = self
        
        sessions[peerId] = newSession
        sessionToPeerId[newSession] = peerId

        if let peerConfig = configuration as? NINearbyPeerConfiguration {
            peerTokenToId[peerConfig.peerDiscoveryToken] = peerId
        }
        
        newSession.run(configuration)
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

    func session(_ session: NISession, didGenerateShareableConfigurationData shareableConfigurationData: Data, for object: NINearbyObject) {
        guard let peerId = sessionToPeerId[session] else {
            logger.error("didGenerateShareableConfigurationData called for an unknown session.")
            return
        }
        
        peerTokenToId[object.discoveryToken] = peerId
        
        logger.log("Generated shareable configuration data for peer \(peerId).")
        delegate?.sessionManager(didGenerateShareableConfigurationData: shareableConfigurationData, for: peerId)
    }
      
    internal func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let nearbyObject = nearbyObjects.first else { return }
        
        guard let peerId = peerTokenToId[nearbyObject.discoveryToken] else {
            logger.warning("Received update for an unknown discovery token.")
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
        guard let peerId = sessionToPeerId[session] else { return }
        
        switch reason {
            case .peerEnded:
                logger.log("Peer \(peerId) ended the session.")
            case .timeout:
                logger.log("Session with peer \(peerId) timed out.")
            default:
                logger.log("Session with peer \(peerId) removed for unknown reason: \(reason.rawValue)")
        }

        delegate?.sessionManager(didStop: true, for: peerId)
        session.invalidate()
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
        }
    }
    
    internal func session(_ session: NISession, didInvalidateWith error: Error) {
        guard let peerId = sessionToPeerId.removeValue(forKey: session) else {
            logger.error("An unknown session was invalidated. Error: \(error.localizedDescription)")
            return
        }

        logger.error("Session for peer \(peerId) invalidated with error: \(error.localizedDescription)")
        
        sessions.removeValue(forKey: peerId)
        if let tokenToRemove = peerTokenToId.first(where: { $1 == peerId })?.key {
            peerTokenToId.removeValue(forKey: tokenToRemove)
        }
        
        if let niError = error as? NIError, niError.code == .userDidNotAllow {
            delegate?.sessionManager(permissionRequired: .request)
        } else {
            delegate?.sessionManager(didStop: true, for: peerId)
        }
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
