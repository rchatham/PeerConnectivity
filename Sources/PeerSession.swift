//
//  PeerSession.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

public struct PeerSession {

    // MARK: - Properties -
    
    public let peer: Peer
    public let servicePeer: Peer

    internal let session: MCSession
    fileprivate let eventProducer: PeerSessionEventProducer?

    // MARK: - Computed Properties -

    public var isLocalServiceSession: Bool {
        return peer == servicePeer
    }

    public var isDistantServiceSession: Bool {
        return isLocalServiceSession == false
    }

    public var connectedPeers: [Peer] {
        return session.connectedPeers.map { Peer(peerID: $0, status: .connected) }
    }

    // MARK: - Initializer -

    internal init(peer: Peer, servicePeer: Peer? = nil, eventProducer: PeerSessionEventProducer,
                  securityIdentity identity: [Any]? = nil, encryptionPreference: MCEncryptionPreference = .optional) {
        self.peer = peer
        self.servicePeer = servicePeer ?? peer
        self.eventProducer = eventProducer
        session = MCSession(peer: peer.peerID, securityIdentity: identity, encryptionPreference: encryptionPreference)
        session.delegate = eventProducer
    }

    internal init(peer: Peer, session: MCSession) {
        self.peer = peer
        self.servicePeer = peer

        self.session = session
        self.eventProducer = session.delegate as? PeerSessionEventProducer
    }

    internal init(session: PeerSession, peer: Peer, servicePeer: Peer? = nil) {
        self.peer = peer
        self.servicePeer = servicePeer ?? peer

        self.session = session.session
        self.eventProducer = session.eventProducer
    }

    init(session: MCSession, sessionPeerStatus: Peer.Status = .connected) {
        let sessionPeer = Peer(peerID: session.myPeerID, status: sessionPeerStatus)
        self.init(peer: sessionPeer, session: session)
    }

    // MARK: - Session Management -
    
    internal func startSession() {
        session.delegate = eventProducer
    }
    
    internal func stopSession() {
        session.disconnect()
        session.delegate = nil
    }

    // MARK: - Data Transfers -
    
    internal func sendData(_ data: Data, toPeers peers: [Peer] = []) {
        do {
            let peers = peers.isEmpty ? session.connectedPeers : peers.map { $0.peerID }

            guard peers.isEmpty == false else {
                return
            }

            try session.send(data, toPeers: peers, with: MCSessionSendDataMode.reliable)
        } catch let error {
            logger.error("session error, sending data - error: \(error)")
        }
    }
    
    internal func sendDataStream(_ streamName: String, toPeer peer: Peer) throws -> OutputStream {
        do {
            let stream = try session.startStream(withName: streamName, toPeer: peer.peerID)
            return stream
        } catch let error {
            logger.error("session error, starting stream - error: \(error)")
            throw error
        }
    }
    
    internal func sendResourceAtURL(_ resourceURL: URL, withName name: String, toPeer peer: Peer,
                                    withCompletionHandler completion: ((Error?)->Void)?) -> Progress? {
        return session.sendResource(at: resourceURL, withName: name, toPeer: peer.peerID,
                                    withCompletionHandler: completion)
    }
    
    // TODO: - Alternative methods of finding peers not yet supported.
    
    internal func nearbyConnectionDataForPeer(_ peer: Peer,
                                              withCompletionHandler completion: @escaping (Data?, Error?) -> Void) {
        session.nearbyConnectionData(forPeer: peer.peerID,
                                     withCompletionHandler: completion)
    }
    
    internal func connectPeer(_ peer: Peer, withNearbyConnectionData data: Data) {
        session.connectPeer(peer.peerID, withNearbyConnectionData: data)
    }
    
    internal func cancelConnectPeer(_ peer: Peer) {
        session.cancelConnectPeer(peer.peerID)
    }
    
}

// MARK: - Protocols
// MARK: - Hashable, Equatable

extension PeerSession: Hashable, Equatable {

    /// :nodoc:
    public var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)

        return hasher.finalize()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(session)
    }

    /// :nodoc:
    public static func ==(lhs: PeerSession, rhs: PeerSession) -> Bool {
        return lhs.session == rhs.session
    }

    /// :nodoc:
    public static func ==(lhs: PeerSession, rhs: Peer) -> Bool {
        return lhs.session.connectedPeers.contains(rhs.peerID)
    }

}

internal func addressHeap<T: AnyObject>(_ o: T) -> Int {
    return unsafeBitCast(o, to: Int.self)
}

// MARK: - CustomStringConvertible & CustomDebugStringConvertible

extension PeerSession: CustomStringConvertible, CustomDebugStringConvertible {

    public var description: String {
        return debugDescription
    }

    public var debugDescription: String {
        let sessionAddress = String(addressHeap(session), radix: 16, uppercase: false)
        let serviceType = isLocalServiceSession ? "local-service" : "distant-service"

        return "<<\(type(of: self))> session: 0x\(sessionAddress); type = \(serviceType); "
             + "servicePeer = \(servicePeer.peerID); peers = \(connectedPeers.count)>"
    }

}
