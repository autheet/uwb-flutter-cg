/*
Copyright © 2022 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Abstract:
A class that manages peer discovery-token exchange over the local network by using MultipeerConnectivity.

Modified by Christian Greiner
*/

import Flutter
import Foundation
import MultipeerConnectivity
import os

struct MPCSessionConstants {
    static let kKeyIdentity: String = "identity"
}

class MultipeerConnectivityManager: NSObject, MCSessionDelegate, MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate {
    
    // Handlers
    var dataReceivedHandler: ((Data, String) -> Void)?
    var peerConnectedHandler: ((String) -> Void)?
    var peerDisconnectedHandler: ((String) -> Void)?
    var peerFoundHandler: ((_: String) -> Void)?
    var peerLostHandler: ((String) -> Void)?
    var peerInvitedHandler: ((String) -> Void)?
    
    private let mcSession: MCSession
    private let mcAdvertiser: MCNearbyServiceAdvertiser
    private let mcBrowser: MCNearbyServiceBrowser
    
    private let identityString: String
    private var nearbyPeers: [String: MCPeerID] = [:]
    private var localMCPeer: MCPeerID
    private var localPeerId: String
    private let logger = os.Logger(subsystem: "uwb_plugin", category: "MultipeerConnectivityManager")

    private var invitations: [String: ((Bool, MCSession?) -> Void)?] = [:]
    
    init(localPeerId: String, service: String, identity: String) {
        self.localPeerId = localPeerId
        self.localMCPeer = MCPeerID(displayName: localPeerId)
        self.identityString = identity
        self.mcSession = MCSession(peer: localMCPeer, securityIdentity: nil, encryptionPreference: .required)
        
        // Init Adveritiser
        self.mcAdvertiser = MCNearbyServiceAdvertiser(
            peer: localMCPeer,
            discoveryInfo: [
                MPCSessionConstants.kKeyIdentity: identityString
            ],
            serviceType: service
        )
        
        // Init Discovery
        self.mcBrowser = MCNearbyServiceBrowser(peer: localMCPeer, serviceType: service)
        
        super.init()
        
        mcSession.delegate = self
        mcAdvertiser.delegate = self
        mcBrowser.delegate = self
    }
    
    // MARK: - `MPCSession` public methods.
    func startAdvertising() {
        mcAdvertiser.startAdvertisingPeer()
        logger.log("Advertising started.")
    }
    
    func stopAdvertising() {
        mcAdvertiser.stopAdvertisingPeer()
        logger.log("Advertising stoped.")
    }
    
    func startDiscovery() {
        nearbyPeers = [:]
        mcBrowser.startBrowsingForPeers()
        logger.log("Discovery started.")
    }
    
    func stopDiscovery() {
        nearbyPeers = [:]
        mcBrowser.stopBrowsingForPeers()
        logger.log("Discovery stoped.")
    }
    
    func invalidate() {
        stopDiscovery()
        stopAdvertising()
        mcSession.disconnect()
        self.invitations.removeAll()
    }
    
    func restartDiscovery() {
        stopDiscovery()
        stopAdvertising()
        startDiscovery()
        startAdvertising()
    }
    
    func disconnectFromPeer(peerId: String) {
        if nearbyPeers[peerId] == nil {
            logger.warning("Peer \(peerId) not found. Disconnect failed.")
            return
        }
        mcSession.cancelConnectPeer(nearbyPeers[peerId]!)
    }
    
    func sendDataToPeer(data: Data, peerId: String) {
        do {
            NSLog("Send Data to peer: \(peerId)")
            logger.log("Send Data to Peer: \(peerId)")
            let peer = mcSession.connectedPeers.first { (peerObj) -> Bool in
                return peerObj.displayName == peerId
            }
        
            if (peer == nil) {
                // TODO Exception handling
                logger.error("Couldn't find Peer: \(peerId). Failed sending data.")
            }
            
            try mcSession.send(data, toPeers: [peer!], with: .reliable)
            
        } catch let error {
            logger.error("Failed sending data: \(error)")
        }
    }

    func sendData(data: Data, peers: [MCPeerID], mode: MCSessionSendDataMode) {
        do {
            try mcSession.send(data, toPeers: peers, with: mode)
        } catch let error {
            logger.error("Failed sending data: \(error)")
        }
    }

    public func invitePeer(peerId: String) {
        logger.log("Invite Peer \(peerId) to session.")
        guard let peer = nearbyPeers[peerId] else {
            logger.warning("Peer \(peerId) not found. Can't invite peer.")
            return
        }
        mcBrowser.invitePeer(peer, to: mcSession, withContext: nil, timeout: 20)
    }
    
    public func handleInvitation(peerId: String, accept: Bool) throws {
        if let handler = invitations[peerId] {
            logger.log("Peer \(peerId) accepted inivation?: \(accept)")
            handler!(accept, self.mcSession)
        } else {
            // TODO: Throw exceptions
            throw FlutterError(
                code: "\(ErrorCode.oOBCONNECTIONERROR.rawValue)",
                message: "Handler not found.",
                details: nil
            )
        }
    }
    
    // MARK: - `MPCSession` private methods.
    private func peerConnected(peerID: MCPeerID) {
        logger.log("Peer \(peerID.displayName) connected.")
        if let handler = peerConnectedHandler {
            handler(peerID.displayName)
        }
    }

    private func peerDisconnected(peerID: MCPeerID) {
        logger.log("Peer \(peerID.displayName) disconnected.")
        if let handler = peerDisconnectedHandler {
            handler(peerID.displayName)
        }
    }

    // MARK: - `MCSessionDelegate`.
    // Remote peer changed state.
    internal func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
            case .connected:
                peerConnected(peerID: peerID)
            case .notConnected:
                peerDisconnected(peerID: peerID)
            case .connecting:
                break
            @unknown default:
                fatalError("Unhandled MCSessionState")
        }
    }

    // Received data from remote peer.
    internal func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        logger.log("Peer \(peerID.displayName) sent data.")
        if let handler = dataReceivedHandler {
            handler(data, peerID.displayName)
        }
    }

    // Received a byte stream from remote peer.
    internal func session(_ session: MCSession,
                            didReceive stream: InputStream,
                            withName streamName: String,
                            fromPeer peerID: MCPeerID) {
    }
    
    // Start receiving a resource from remote peer.
    internal func session(_ session: MCSession,
                          didStartReceivingResourceWithName resourceName: String,
                          fromPeer peerID: MCPeerID,
                          with progress: Progress) {
    }

    // Finished receiving a resource from remote peer and saved the content
    // in a temporary location - the app is responsible for moving the file
    // to a permanent location within its sandbox.
    internal func session(_ session: MCSession,
                          didFinishReceivingResourceWithName resourceName: String,
                          fromPeer peerID: MCPeerID,
                          at localURL: URL?,
                          withError error: Error?) {
    }

    // MARK: - `MCNearbyServiceBrowserDelegate`.
    // Found a nearby advertising peer.
    internal func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let identityValue = info?[MPCSessionConstants.kKeyIdentity] else {
            return
        }
        
        if identityValue == identityString {
            
            logger.log("Discovered Peer \(peerID.displayName) found.")
            nearbyPeers[peerID.displayName] = peerID
            if let handler = peerFoundHandler {
                handler(peerID.displayName)
            }
        }
    }
    
    // A nearby peer has stopped advertising.
    internal func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logger.log("Peer \(peerID.displayName) lost.")
        nearbyPeers.removeValue(forKey: peerID.displayName)
        if let handler = peerLostHandler {
            handler(peerID.displayName)
        }
    }

    // MARK: - `MCNearbyServiceAdvertiserDelegate`.
    // Incoming invitation request. Call the invitationHandler block with YES
    // and a valid session to connect the inviting peer to the session.
    internal func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                             didReceiveInvitationFromPeer peerID: MCPeerID,
                             withContext context: Data?,
                             invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        
        logger.log("Incoming inivation request by \(peerID.displayName).")
        
        self.invitations[peerID.displayName] = invitationHandler
        
        if let handler = peerInvitedHandler {
            handler(peerID.displayName)
        }
    }
}
