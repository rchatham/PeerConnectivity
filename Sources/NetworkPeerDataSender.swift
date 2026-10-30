//
//  NetworkPeerDataSender.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

internal protocol NetworkPeerFrameSending : NetworkPeerConnectionCancellable {
    func sendFrame(_ frame: PeerNetworkFrame, onProcessed: @escaping (Error?) -> Void)
}

extension NetworkPeerFrameSending {
    internal func sendFrame(_ frame: PeerNetworkFrame) {
        sendFrame(frame, onProcessed: { _ in })
    }
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

    /// Completes once every target connection has processed the frame. Targets without a
    /// registered connection fail with `PeerConnectionError.peerNotConnected`.
    internal func sendData(_ data: Data,
        toPeers peers: [PeerIdentity],
        completion: @escaping ([PeerIdentity:Error]) -> Void) {
        let identities = peers.isEmpty ? registry.connectedPeerIdentities : peers
        let frame = PeerNetworkFrame(kind: .data, payload: data)
        let group = DispatchGroup()
        let failuresLock = NSLock()
        var failures : [PeerIdentity:Error] = [:]

        identities.forEach { identity in
            guard let connection = registry.connection(for: identity) else {
                failuresLock.locked {
                    failures[identity] = PeerConnectionError.peerNotConnected(Peer(identity: identity, status: .notConnected))
                }
                return
            }
            group.enter()
            connection.sendFrame(frame) { error in
                if let error = error {
                    failuresLock.locked { failures[identity] = error }
                }
                group.leave()
            }
        }
        group.notify(queue: DispatchQueue.global()) {
            completion(failuresLock.locked { failures })
        }
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension NetworkPeerConnection : NetworkPeerFrameSending {
    internal func sendFrame(_ frame: PeerNetworkFrame, onProcessed: @escaping (Error?) -> Void) {
        sendFrame(frame, completion: { error in onProcessed(error) })
    }
}
