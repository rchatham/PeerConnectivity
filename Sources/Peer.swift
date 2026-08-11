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
     Returns whether a display name satisfies MultipeerConnectivity's documented constraints.

     Display names are visible to nearby peers. Avoid personal device names, email addresses,
     stable user identifiers, or other sensitive information when choosing a display name.

     - parameter displayName: Display name string to validate.
     - Returns: `true` when the display name is non-empty and no more than 63 bytes when UTF-8 encoded.
     */
    public static func isValidDisplayName(_ displayName: String) -> Bool {
        return !displayName.isEmpty && displayName.lengthOfBytes(using: .utf8) <= 63
    }
    
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
     The peer's display name. Display names are visible to nearby peers.
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
    
    /**
     Initializer for a peer backed by an existing MultipeerConnectivity peer identifier.

     - parameter peerID: Existing MultipeerConnectivity peer identifier.
     - parameter status: The peer's connection status.
     */
    public init(peerID: MCPeerID, status: Status) {
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
     Initializer for the local peer. Display names must not be longer than 63 bytes in UTF-8 encoding and are visible to nearby peers.
     */
    internal init(displayName: String) {
        peerID = MCPeerID(displayName: displayName)
        identity = PeerIdentity(peerID: peerID)
        status = .currentUser
    }
}

extension PeerIdentity {
    internal init(peerID: MCPeerID) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: peerID, requiringSecureCoding: true) else {
            preconditionFailure("PeerConnectivity: Failed to archive MCPeerID using secure coding")
        }
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
