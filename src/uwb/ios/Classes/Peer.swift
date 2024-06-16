//
//  Peer.swift
//  uwb
//
//  Created by Christian Greiner on 13.03.24.
//
import NearbyInteraction

// Used for MPC
struct Peer {
    var id: String
    var name: String
}

struct NIPeer {
    var peer: Peer
    var session: NISession
    var peerDiscoveryToken: NIDiscoveryToken?
    var peerType: DeviceType
}
