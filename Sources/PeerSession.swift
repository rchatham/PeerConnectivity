//
//  PeerSession.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal struct PeerSession {
    
    internal let peer : Peer
    internal let session : MCSession
    fileprivate let eventProducer: PeerSessionEventProducer
    
    internal var connectedPeers : [Peer] {
        return session.connectedPeers.map { Peer(peerID: $0, status: .connected) }
    }
    
    internal init(peer: Peer, eventProducer: PeerSessionEventProducer) {
        self.peer = peer
        self.eventProducer = eventProducer
        session = MCSession(peer: peer.peerID, securityIdentity: nil, encryptionPreference: .optional)
        session.delegate = eventProducer
    }
    
    internal func startSession() {
        session.delegate = eventProducer
    }
    
    internal func stopSession() {
        session.disconnect()
        session.delegate = nil
    }
    
    internal func sendData(_ data: Data, toPeers peers: [Peer] = []) {
        do {
            try session.send(data,
                toPeers: peers.isEmpty
                    ? session.connectedPeers
                    : peers.map { $0.peerID },
                with: MCSessionSendDataMode.reliable)
        } catch let error {
            NSLog("%@", "Error sending data: \(error)")
        }
    }
    
    internal func sendDataStream(_ streamName: String, toPeer peer: Peer) throws -> OutputStream {
        do {
            let stream = try session.startStream(withName: streamName, toPeer: peer.peerID)
            return stream
        } catch let error {
            NSLog("%@", "Error starting stream to \(peer.displayName): \(error)")
            throw error
        }
    }
    
    internal func sendResourceAtURL(_ resourceURL: URL,
        withName name: String,
        toPeer peer: Peer,
        withCompletionHandler completion: ((Error?)->Void)?) -> Progress? {
        
        return session.sendResource(at: resourceURL,
            withName: name,
            toPeer: peer.peerID,
            withCompletionHandler: completion)
    }
    
    // TODO: - Alternative methods of finding peers not yet supported.
    
    internal func nearbyConnectionDataForPeer(_ peer: Peer, withCompletionHandler completion: @escaping (Data, Error?)->Void) {
        session.nearbyConnectionData(forPeer: peer.peerID, withCompletionHandler: completion)
    }
    
    internal func connectPeer(_ peer: Peer, withNearbyConnectionData data: Data) {
        session.connectPeer(peer.peerID, withNearbyConnectionData: data)
    }
    
    internal func cancelConnectPeer(_ peer: Peer) {
        session.cancelConnectPeer(peer.peerID)
    }
    
}
