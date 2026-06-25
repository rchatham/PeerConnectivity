//
//  NetworkPeerDataSender.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

internal protocol NetworkPeerFrameSending : NetworkPeerConnectionCancellable {
    func sendFrame(_ frame: PeerNetworkFrame)
}

internal final class NetworkPeerDataSender<Connection: NetworkPeerFrameSending> {

    fileprivate let registry : NetworkPeerConnectionRegistry<Connection>

    internal init(registry: NetworkPeerConnectionRegistry<Connection>) {
        self.registry = registry
    }

    internal func sendData(_ data: Data, toPeers peers: [PeerIdentity] = []) {
        let identities = peers.isEmpty ? registry.connectedPeerIdentities : peers
        let frame = PeerNetworkFrame(kind: .data, payload: data)
        identities.forEach { identity in
            registry.connection(for: identity)?.sendFrame(frame)
        }
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension NetworkPeerConnection : NetworkPeerFrameSending {
    internal func sendFrame(_ frame: PeerNetworkFrame) {
        sendFrame(frame, completion: nil)
    }
}
