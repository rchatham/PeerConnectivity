//
//  Peer.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/19/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

/**
 Struct reperesenting a user available for mesh-networking on the PeerConnectivity framework.
 */
public struct Peer {
    
    /**
     Peer connection status.
     */
    public enum Status {
        /**
         Represents the current user.
         */
        case currentUser
        /**
         Represents a connected user.
         */
        case connected
        /**
         Represents a connecting user.
         */
        case connecting
        /**
         Represents a user not connected to the current session. Either someone that is available to be invited to the current session or someone that has lost connection to the current session.
         */
        case notConnected
    }
    
    /**
     The peer's display name
     */
    public var displayName : String {
        return identity.displayName
    }
    
    
    
    internal let identity : PeerIdentity
    internal let peerID : MCPeerID
    
    /**
     The connection status to a particular user.
     */
    public let status : Status
    
    internal init(peerID: MCPeerID, status: Status) {
        self.identity = PeerIdentity(peerID: peerID)
        self.peerID = peerID
        self.status = status
    }

    internal init(identity: PeerIdentity, status: Status) {
        self.identity = identity
        self.peerID = MCPeerID(displayName: identity.displayName)
        self.status = status
    }
    
    /**
     Initializer for the local peer. DisplayName Must not be longer than 63 bytes in UTF8 Encoding according to the Apple documentation. ( xcdoc://?url=developer.apple.com/library/ios/documentation/MultipeerConnectivity/Reference/MCPeerID_class/index.html#//apple_ref/swift/cl/c:objc(cs)MCPeerID )
     */
    internal init(displayName: String) {
        peerID = MCPeerID(displayName: displayName)
        identity = PeerIdentity(peerID: peerID)
        status = .currentUser
    }
}

extension PeerIdentity {
    internal init(peerID: MCPeerID) {
        let data = NSKeyedArchiver.archivedData(withRootObject: peerID)
        self.init(identifier: data.base64EncodedString(), displayName: peerID.displayName)
    }
}

extension Peer : Hashable, Equatable {
    /// :nodoc:
    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }

    /// :nodoc:
    public static func ==(lhs: Peer, rhs: Peer) -> Bool {
        return lhs.identity == rhs.identity
    }
}
