//
//  NetworkPeerConnectionRegistry.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

internal protocol NetworkPeerConnectionCancellable : AnyObject {
    func cancel()
}

internal enum NetworkPeerConnectionDirection {
    case inbound
    case outbound
}

internal final class NetworkPeerConnectionRegistry<Connection: NetworkPeerConnectionCancellable> {

    internal typealias DuplicateResolver = (_ local: PeerIdentity,
        _ remote: PeerIdentity,
        _ existing: NetworkPeerConnectionDirection,
        _ incoming: NetworkPeerConnectionDirection) -> NetworkPeerConnectionDirection

    fileprivate struct Entry {
        internal let connection : Connection
        internal let direction : NetworkPeerConnectionDirection
    }

    fileprivate let localIdentity : PeerIdentity
    fileprivate let duplicateResolver : DuplicateResolver
    fileprivate var entries : [PeerIdentity:Entry] = [:]

    internal init(localIdentity: PeerIdentity,
        duplicateResolver: @escaping DuplicateResolver = NetworkPeerConnectionRegistry.defaultDuplicateResolver) {
        self.localIdentity = localIdentity
        self.duplicateResolver = duplicateResolver
    }

    internal var connectedPeerIdentities : [PeerIdentity] {
        return Array(entries.keys)
    }

    internal func connection(for identity: PeerIdentity) -> Connection? {
        return entries[identity]?.connection
    }

    @discardableResult
    internal func register(_ connection: Connection,
        for identity: PeerIdentity,
        direction: NetworkPeerConnectionDirection) -> Bool {
        guard let existing = entries[identity] else {
            entries[identity] = Entry(connection: connection, direction: direction)
            return true
        }

        let winningDirection = duplicateResolver(localIdentity, identity, existing.direction, direction)
        if winningDirection == existing.direction {
            connection.cancel()
            return false
        } else {
            existing.connection.cancel()
            entries[identity] = Entry(connection: connection, direction: direction)
            return true
        }
    }

    internal func remove(identity: PeerIdentity) {
        entries.removeValue(forKey: identity)
    }

    internal func cancelAll() {
        entries.values.forEach { $0.connection.cancel() }
        entries = [:]
    }

    internal static func defaultDuplicateResolver(local: PeerIdentity,
        remote: PeerIdentity,
        existing: NetworkPeerConnectionDirection,
        incoming: NetworkPeerConnectionDirection) -> NetworkPeerConnectionDirection {
        guard existing != incoming else { return existing }
        let shouldPreferOutbound = local.identifier < remote.identifier
        return shouldPreferOutbound ? .outbound : .inbound
    }
}
