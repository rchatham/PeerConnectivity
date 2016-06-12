//
//  PeerSession.swift
//  GameController
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal struct PeerSession {
    
    internal let peer : Peer
    internal let session : MCSession
    private let eventProducer: PeerSessionEventProducer
    
    internal var connectedPeers : [Peer] {
        return session.connectedPeers.map { Peer.Connected($0) }
    }
    
    internal init(peer: Peer, eventProducer: PeerSessionEventProducer) {
        self.peer = peer
        self.eventProducer = eventProducer
        session = MCSession(peer: peer.peerID, securityIdentity: nil, encryptionPreference: .Optional)
        session.delegate = eventProducer
    }
    
    internal func startSession() {
        session.delegate = eventProducer
    }
    
    internal func stopSession() {
        session.disconnect()
        session.delegate = nil
    }
    
    internal func sendData(data: NSData, toPeers peers: [Peer] = []) {
        do {
            try session.sendData(data,
                toPeers: peers.isEmpty
                    ? session.connectedPeers
                    : peers.map { $0.peerID },
                withMode: MCSessionSendDataMode.Reliable)
        } catch let error {
            NSLog("%@", "Error sending data: \(error)")
        }
    }
    
    internal func sendDataStream(streamName: String, toPeer peer: Peer) throws -> NSOutputStream {
        do {
            let stream = try session.startStreamWithName(streamName, toPeer: peer.peerID)
            return stream
        } catch let error {
            NSLog("%@", "Error starting stream to \(peer.displayName): \(error)")
            throw error
        }
    }
    
    internal func sendResourceAtURL(resourceURL: NSURL,
        withName name: String,
        toPeer peer: Peer,
        withCompletionHandler completion: ((NSError?)->Void)?) -> NSProgress? {
        
        return session.sendResourceAtURL(resourceURL,
            withName: name,
            toPeer: peer.peerID,
            withCompletionHandler: completion)
    }
    
    internal func nearbyConnectionDataForPeer(peer: Peer, withCompletionHandler completion: (NSData, NSError?)->Void) {
        session.nearbyConnectionDataForPeer(peer.peerID, withCompletionHandler: completion)
    }
    
    internal func connectPeer(peer: Peer, withNearbyConnectionData data: NSData) {
        session.connectPeer(peer.peerID, withNearbyConnectionData: data)
    }
    
    internal func cancelConnectPeer(peer: Peer) {
        session.cancelConnectPeer(peer.peerID)
    }
    
}