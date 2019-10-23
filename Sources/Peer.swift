//
//  Peer.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/19/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

/// Struct reperesenting a user available for mesh-networking on the PeerConnectivity framework.
public struct Peer {

    // MARK: - Nested Types -

    /// Peer connection status.
    public enum Status {

        /// Represents the current user.
        case currentUser

        /// Represent a service peer (found through browser)
        case available

        /// Represent a unavailable peer (lostPeer not received from browser)
        case unavailable

        // -

        /// Represents a connected user.
        case connected

        /// Represents a connecting user.
        case connecting

        /// Represents a user not connected to the current session.
        /// Either someone that is available to be invited to the current session or
        ///     someone that has lost connection to the current session.
        case notConnected

        // MARK: - Initializers

        init(state: MCSessionState) {
            switch state {
            case .notConnected: self = .notConnected
            case .connecting: self = .connecting
            case .connected: self = .connected
            @unknown default: self = .notConnected
            }
        }

    }

    // MARK: - Properties -

    public let peerID: MCPeerID
    
    /// The connection status to a particular user.
    public let status: Status

    /// Service discovery informations, if peers represent service from NearbyServiceBrowser
    public let serviceDiscoveryInfo: DiscoveryInfo?

    // MARK: - Computed Properties -

    /// The peer's display name
    public var displayName: String {
        return peerID.displayName
    }

    // MARK: - Initializers -

    internal init(peerID: MCPeerID, status: Status, info: DiscoveryInfo? = nil) {
        self.peerID = peerID
        self.status = status
        self.serviceDiscoveryInfo = info
    }

    internal init(peer: Peer, status: Status) {
        self.status = status
        self.peerID = peer.peerID
        self.serviceDiscoveryInfo = peer.serviceDiscoveryInfo
    }

    /// Initializer for the local peer.
    /// DisplayName Must not be longer than 63 bytes in UTF8 Encoding according to the Apple documentation.
    /// [MCPeerID reference](xcdoc://?url=developer.apple.com/library/ios/documentation/MultipeerConnectivity/Reference/MCPeerID_class/index.html#//apple_ref/swift/cl/c:objc(cs)MCPeerID)
    internal init(displayName: String) {
        self.status = .currentUser
        self.serviceDiscoveryInfo = nil
        self.peerID = MCPeerID(displayName: displayName)
    }
}

// MARK: - Protocols
// MARK: - Hashable, Equatable

extension Peer: Hashable, Equatable {

    /// :nodoc:
    public var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)

        return hasher.finalize()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(peerID)
    }

    /// :nodoc:
    public static func ==(lhs: Peer, rhs: Peer) -> Bool {
        return lhs.peerID == rhs.peerID
    }

    /// :nodoc:
    public static func ===(lhs: Peer, rhs: Peer) -> Bool {
        return lhs.peerID === rhs.peerID
    }

}
