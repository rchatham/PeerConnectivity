//
//  NetworkPeerCoordinator.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

internal final class NetworkPeerCoordinator<Connection: NetworkPeerFrameSending> {

    internal typealias HandshakeEncoder = (PeerNetworkHandshake) throws -> Data

    fileprivate struct PendingConnection {
        internal let connection : Connection
        internal let direction : NetworkPeerConnectionDirection
    }

    fileprivate let localPeer : Peer
    fileprivate let registry : NetworkPeerConnectionRegistry<Connection>
    fileprivate let dataSender : NetworkPeerDataSender<Connection>
    fileprivate let queue = DispatchQueue(label: "PeerConnectivity.NetworkPeerCoordinator")
    fileprivate let sessionObserver : Observable<PeerSessionEvent>
    fileprivate let handshakeEncoder : HandshakeEncoder
    fileprivate var pendingConnections : [ObjectIdentifier:PendingConnection] = [:]
    internal static var maxPendingConnections : Int { 32 }
    fileprivate let handshakeTimeout : TimeInterval
    fileprivate var connectionIdentities : [ObjectIdentifier:PeerIdentity] = [:]

    internal init(localPeer: Peer,
        sessionObserver: Observable<PeerSessionEvent>,
        handshakeTimeout: TimeInterval = 10,
        handshakeEncoder: @escaping HandshakeEncoder = { try JSONEncoder().encode($0) }) {
        self.localPeer = localPeer
        self.registry = NetworkPeerConnectionRegistry(localIdentity: localPeer.identity)
        self.dataSender = NetworkPeerDataSender(registry: registry)
        self.sessionObserver = sessionObserver
        self.handshakeTimeout = handshakeTimeout
        self.handshakeEncoder = handshakeEncoder
    }

    internal var connectedPeers : [Peer] {
        return queue.sync {
            registry.connectedPeerIdentities.map { Peer(identity: $0, status: .connected) }
        }
    }

    internal func addPendingConnection(_ connection: Connection, direction: NetworkPeerConnectionDirection) {
        queue.sync {
            let identifier = ObjectIdentifier(connection)
            guard pendingConnections.count < Self.maxPendingConnections,
                pendingConnections[identifier] == nil,
                connectionIdentities[identifier] == nil else {
                connection.cancel()
                return
            }
            pendingConnections[identifier] = PendingConnection(connection: connection, direction: direction)
            queue.asyncAfter(deadline: .now() + handshakeTimeout) { [weak self, weak connection] in
                guard let self = self, let connection = connection,
                    self.pendingConnections.removeValue(forKey: identifier) != nil else { return }
                connection.cancel()
            }
            sendHandshake(on: connection)
        }
    }

    internal func receiveFrame(_ frame: PeerNetworkFrame, from connection: Connection) {
        queue.sync {
            switch frame.kind {
            case .handshake:
                receiveHandshake(frame.payload, from: connection)
            case .data:
                receiveData(frame.payload, from: connection)
            }
        }
    }

    internal func sendData(_ data: Data, toPeers peers: [Peer] = []) {
        queue.sync {
            dataSender.sendData(data, toPeers: peers.map { $0.identity })
        }
    }

    internal func removeConnection(_ connection: Connection) {
        queue.sync {
            let identifier = ObjectIdentifier(connection)
            pendingConnections.removeValue(forKey: identifier)
            guard let identity = connectionIdentities.removeValue(forKey: identifier) else { return }
            guard registry.connection(for: identity) === connection else { return }
            registry.remove(identity: identity)
            sessionObserver.update(.devicesChanged(peer: Peer(identity: identity, status: .notConnected)))
        }
    }

    internal func cancelAllConnections() {
        queue.sync {
            pendingConnections.values.forEach { $0.connection.cancel() }
            pendingConnections.removeAll()
            connectionIdentities.removeAll()
            registry.cancelAll()
        }
    }


    fileprivate func receiveHandshake(_ data: Data, from connection: Connection) {
        guard let handshake = try? JSONDecoder().decode(PeerNetworkHandshake.self, from: data),
            handshake.protocolVersion == PeerNetworkHandshake.currentProtocolVersion else {
            rejectHandshake(from: connection)
            return
        }

        guard PeerIdentity.isValidIdentifier(handshake.identity.identifier),
            Peer.isValidDisplayName(handshake.identity.displayName),
            handshake.identity != localPeer.identity else {
            rejectHandshake(from: connection)
            return
        }

        let identifier = ObjectIdentifier(connection)
        if let registeredIdentity = connectionIdentities[identifier] {
            guard registeredIdentity != handshake.identity else { return }
            connectionIdentities.removeValue(forKey: identifier)
            if registry.connection(for: registeredIdentity) === connection {
                registry.remove(identity: registeredIdentity)
                sessionObserver.update(.devicesChanged(peer: Peer(identity: registeredIdentity, status: .notConnected)))
            }
            connection.cancel()
            return
        }
        guard let pending = pendingConnections.removeValue(forKey: identifier) else {
            connection.cancel()
            return
        }
        let direction = pending.direction
        let wasConnected = registry.connection(for: handshake.identity) != nil
        let isRegistered = registry.register(connection, for: handshake.identity, direction: direction)
        guard isRegistered else { return }

        removeConnectionIdentity(for: handshake.identity)
        connectionIdentities[identifier] = handshake.identity
        guard !wasConnected else { return }
        sessionObserver.update(.devicesChanged(peer: Peer(identity: handshake.identity, status: .connected)))
    }

    fileprivate func rejectHandshake(from connection: Connection) {
        let identifier = ObjectIdentifier(connection)
        guard pendingConnections.removeValue(forKey: identifier) != nil else { return }
        connection.cancel()
    }

    fileprivate func removeConnectionIdentity(for identity: PeerIdentity) {
        connectionIdentities = connectionIdentities.filter { $0.value != identity }
    }

    fileprivate func receiveData(_ data: Data, from connection: Connection) {
        guard let identity = connectionIdentities[ObjectIdentifier(connection)] else { return }
        sessionObserver.update(.didReceiveData(peer: Peer(identity: identity, status: .connected), data: data))
    }

    fileprivate func sendHandshake(on connection: Connection) {
        let handshake = PeerNetworkHandshake(identity: localPeer.identity)

        do {
            let payload = try handshakeEncoder(handshake)
            connection.sendFrame(PeerNetworkFrame(kind: .handshake, payload: payload))
        } catch {
            NSLog("%@", "PeerConnectivity: Failed to encode Network handshake; canceling connection")
            rejectHandshake(from: connection)
        }
    }
}
