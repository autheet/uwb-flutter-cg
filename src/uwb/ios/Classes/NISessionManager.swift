import Foundation
import NearbyInteraction
import MultipeerConnectivity
import os

class NISessionManager: NSObject, NISessionDelegate {
        
    var rangingDataCallback: ((String, UwbRangingData) -> Void)?
    var uwbSessionStopped: ((String) -> Void)?
    var permissionRequiredHandler: ((PermissionAction) -> Void)?
    
    private var sessions = [String: NIPeer]()
    
    private let logger = os.Logger(subsystem: "uwb_plugin", category: "NISessionManager")
  
    public func isDeviceRanging(deviceId: String) -> Bool {
        return sessions.keys.contains(deviceId)
    }
    
    public func invalidateSessions() {
        for niPeer in sessions.values {
            niPeer.session.invalidate()
        }
    }
    
    public func initPhoneSession(peer: Peer) -> NIDiscoveryToken? {
        let peerSession = NISession()
        peerSession.delegate = self
        
        guard let myToken = peerSession.discoveryToken else {
            logger.error("Session is invalid. Can't access discovery token.")
            return nil
        }
        
        logger.log("Init NI Session with Peer: \(peer.id)")
        
        sessions[peer.id] = NIPeer(
            peer: peer,
            session: peerSession,
            peerType: DeviceType.smartphone
        )
        return myToken
    }
    
    public func stopSession(peerId: String) {
        if !sessions.keys.contains(peerId) {
            logger.error("Peer \(peerId) doesn't exists.")
            return
        }
        
        self.sessions[peerId]?.session.invalidate()
        self.sessions.removeValue(forKey: peerId)
    }
    
    public func stopSessions() {
        for niPeer in sessions.values {
            niPeer.session.invalidate()
            sessions.removeValue(forKey: niPeer.peer.id)
        }
    }
    
    public func startSessionWithPhone(peerId: String, peerDiscoveryToken: NIDiscoveryToken, config: UwbSessionConfig) {
        guard sessions[peerId] != nil else {
            logger.error("Session with \(peerId) doesn't exists.")
            return
        }
        
        sessions[peerId]?.peerDiscoveryToken = peerDiscoveryToken
        
        let config = NINearbyPeerConfiguration(peerToken: peerDiscoveryToken)
        if #available(iOS 16.0, *) {
            config.isCameraAssistanceEnabled = true
        }
        
        logger.log("Start NISession with \(peerId).")
        
        // Run the session.
        sessions[peerId]!.session.run(config)
    }
      
    internal func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let nearbyObject = nearbyObjects.first else { return }
        guard let niPeer = getNIPeerByDiscoveryToken(session: session) else {
            return
        }
        
        if nearbyObject.distance == nil && nearbyObject.direction == nil {
            return
        }
        
        var horizontalAngle: Double? = nil
        if #available(iOS 16.0, *) {
            if let angle = nearbyObject.horizontalAngle {
                horizontalAngle = Double(angle)
            }
        }
        
        var azimuth: Double? = nil
        var elevation: Double? = nil
        var direction: Direction3D? = nil
        if (nearbyObject.direction != nil) {
            let dir = nearbyObject.direction!
            azimuth = Double(asin(dir.x))
            elevation = Double(atan2(dir.z, dir.y) + .pi / 2)
            direction = Direction3D(x: Double(dir.x), y: Double(dir.y), z: Double(dir.z))
        }

        let rangingData = UwbRangingData(
            distance: nearbyObject.distance.map { Double($0) },
            azimuth: azimuth,
            elevation: elevation,
            direction: direction,
            horizontalAngle: horizontalAngle
        )
        
        rangingDataCallback?(niPeer.peer.id, rangingData)
    }
    
    private func getNIPeerByDiscoveryToken(session: NISession) -> NIPeer? {
        let niPeer = sessions.values.first(where: { (niPeer) -> Bool in
            return niPeer.session.discoveryToken == session.discoveryToken
        })
        return niPeer
    }

    internal func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard reason == .timeout || reason == .peerEnded else { return }
        logger.info("Session ended with reason: \(reason.rawValue)")

        guard let niPeer = getNIPeerByDiscoveryToken(session: session) else {
            return
        }
        
        self.sessions[niPeer.peer.id]?.session.invalidate()
        self.sessions.removeValue(forKey: niPeer.peer.id)
        
        uwbSessionStopped?(niPeer.peer.id)
    }
    
    internal func sessionWasSuspended(_ session: NISession) {
        let niPeer = getNIPeerByDiscoveryToken(session: session)
        logger.warning("Session is suspended: \(niPeer!.peer.id)")
    }

    internal func sessionSuspensionEnded(_ session: NISession) {
        let niPeer = getNIPeerByDiscoveryToken(session: session)
                
        logger.log("Session suspended ended: \(niPeer!.peer.id)")

        if niPeer == nil {
            return
        }
        
        logger.log("Try to rerun the session with peer: \(niPeer!.peer.id)")
        if let config = niPeer?.session.configuration {
            logger.log("Rerun session with peer: \(niPeer!.peer.id)")
            session.run(config)
        } else {
            logger.warning("Needs to init a new session with Peer: \(niPeer!.peer.id)")
        }
    }
    
    internal func session(_ session: NISession, didInvalidateWith error: Error) {
        logger.warning("Session is invalidated. Reason: \(error.localizedDescription)")
        
        if case NIError.userDidNotAllow = error {
            if #available(iOS 15.0, *) {
                permissionRequiredHandler?(.request)
            }
            return
        }
        
        let niPeer = getNIPeerByDiscoveryToken(session: session)
        
        if niPeer == nil {
            return
        }
        
        self.sessions[niPeer!.peer.id]?.session.invalidate()
        self.sessions.removeValue(forKey: niPeer!.peer.id)
    }
    
    func sessionDidStartRunning(_ session: NISession) {}
}

class NIPeer {
    let peer: Peer
    let peerType: DeviceType
    var session: NISession
    var peerDiscoveryToken: NIDiscoveryToken?
    
    init(peer: Peer, session: NISession, peerType: DeviceType) {
        self.peer = peer
        self.session = session
        self.peerType = peerType
    }
}
