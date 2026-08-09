//
//  NetworkPeerCoordinator.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

internal struct NetworkPeerConnectionPolicy : Equatable {
    internal let handshakeTimeout : TimeInterval
    internal let maxPendingConnections : Int
    internal let maxConnectedPeers : Int

    internal init(handshakeTimeout: TimeInterval = 10,
        maxPendingConnections: Int = 16,
        maxConnectedPeers: Int = 8) {
        precondition(handshakeTimeout > 0, "PeerConnectivity: Network handshake timeout must be positive")
        precondition(maxPendingConnections > 0, "PeerConnectivity: Network pending connection limit must be positive")
        precondition(maxConnectedPeers > 0, "PeerConnectivity: Network connected peer limit must be positive")
        self.handshakeTimeout = handshakeTimeout
        self.maxPendingConnections = maxPendingConnections
        self.maxConnectedPeers = maxConnectedPeers
    }
}

internal final class NetworkPeerCoordinator<Connection: NetworkPeerFrameSending> {

    fileprivate struct PendingConnection {
        internal let connection : Connection
        internal let direction : NetworkPeerConnectionDirection
        internal let timeout : DispatchWorkItem
    }

    fileprivate let localPeer : Peer
    fileprivate let registry : NetworkPeerConnectionRegistry<Connection>
    fileprivate let dataSender : NetworkPeerDataSender<Connection>
    fileprivate let queue = DispatchQueue(label: "PeerConnectivity.NetworkPeerCoordinator")
    fileprivate let sessionObserver : Observable<PeerSessionEvent>
    fileprivate let browserObserver : Observable<PeerBrowserEvent>
    fileprivate let advertiserObserver : Observable<PeerAdvertiserEvent>
    fileprivate let policy : NetworkPeerConnectionPolicy
    fileprivate var pendingConnections : [ObjectIdentifier:PendingConnection] = [:]
    fileprivate var connectionIdentities : [ObjectIdentifier:PeerIdentity] = [:]
    fileprivate var discoveredPeers : [PeerIdentity:Peer] = [:]

    internal init(localPeer: Peer,
        sessionObserver: Observable<PeerSessionEvent>,
        browserObserver: Observable<PeerBrowserEvent>,
        advertiserObserver: Observable<PeerAdvertiserEvent>,
        policy: NetworkPeerConnectionPolicy = NetworkPeerConnectionPolicy()) {
        self.localPeer = localPeer
        self.registry = NetworkPeerConnectionRegistry(localIdentity: localPeer.identity)
        self.dataSender = NetworkPeerDataSender(registry: registry)
        self.sessionObserver = sessionObserver
        self.browserObserver = browserObserver
        self.advertiserObserver = advertiserObserver
        self.policy = policy
    }

    internal var connectedPeers : [Peer] {
        return queue.sync {
            registry.connectedPeerIdentities.map { Peer(identity: $0, status: .connected) }
        }
    }

    internal func addPendingConnection(_ connection: Connection, direction: NetworkPeerConnectionDirection) {
        queue.sync {
            guard registry.connectedPeerIdentities.count < policy.maxConnectedPeers,
                pendingConnections.count < policy.maxPendingConnections else {
                connection.cancel()
                return
            }
            let identifier = ObjectIdentifier(connection)
            pendingConnections[identifier]?.timeout.cancel()
            let timeout = DispatchWorkItem { [weak self, weak connection] in
                guard let connection = connection else { return }
                self?.expirePendingConnection(connection)
            }
            pendingConnections[identifier] = PendingConnection(connection: connection,
                direction: direction,
                timeout: timeout)
            queue.asyncAfter(deadline: .now() + policy.handshakeTimeout, execute: timeout)
            sendHandshake(on: connection)
        }
    }

    internal func receiveFrame(_ frame: PeerNetworkFrame, from connection: Connection) {
        let event : PeerSessionEvent? = queue.sync {
            switch frame.kind {
            case .handshake:
                return receiveHandshake(frame.payload, from: connection)
            case .data:
                return receiveData(frame.payload, from: connection)
            }
        }
        guard let event = event else { return }
        sessionObserver.value = event
    }

    internal func sendData(_ data: Data, toPeers peers: [Peer] = []) {
        queue.sync {
            dataSender.sendData(data, toPeers: peers.map { $0.identity })
        }
    }

    internal func removeConnection(_ connection: Connection) {
        let event : PeerSessionEvent? = queue.sync {
            let identifier = ObjectIdentifier(connection)
            pendingConnections.removeValue(forKey: identifier)?.timeout.cancel()
            guard let identity = connectionIdentities.removeValue(forKey: identifier) else { return nil }
            guard registry.connection(for: identity) === connection else { return nil }
            registry.remove(identity: identity)
            return .devicesChanged(peer: Peer(identity: identity, status: .notConnected))
        }
        guard let event = event else { return }
        sessionObserver.value = event
    }

    internal func cancelAllConnections() {
        queue.sync {
            pendingConnections.values.forEach {
                $0.timeout.cancel()
                $0.connection.cancel()
            }
            pendingConnections.removeAll()
            connectionIdentities.removeAll()
            registry.cancelAll()
        }
    }

    internal func foundPeer(identity: PeerIdentity) {
        let event : PeerBrowserEvent? = queue.sync {
            guard identity != localPeer.identity else { return nil }
            let peer = Peer(identity: identity, status: .notConnected)
            discoveredPeers[identity] = peer
            return .foundPeer(peer, discoveryInfo: nil)
        }
        guard let event = event else { return }
        browserObserver.value = event
    }

    internal func lostPeer(identity: PeerIdentity) {
        let event : PeerBrowserEvent? = queue.sync {
            guard identity != localPeer.identity else { return nil }
            let peer = discoveredPeers.removeValue(forKey: identity) ?? Peer(identity: identity, status: .notConnected)
            return .lostPeer(peer)
        }
        guard let event = event else { return }
        browserObserver.value = event
    }

    fileprivate func receiveHandshake(_ data: Data, from connection: Connection) -> PeerSessionEvent? {
        guard let handshake = try? JSONDecoder().decode(PeerNetworkHandshake.self, from: data),
            handshake.protocolVersion == PeerNetworkHandshake.currentProtocolVersion else {
            rejectHandshake(from: connection)
            return nil
        }

        guard handshake.identity != localPeer.identity else {
            rejectHandshake(from: connection)
            return nil
        }

        let identifier = ObjectIdentifier(connection)
        let pending = pendingConnections.removeValue(forKey: identifier)
        pending?.timeout.cancel()
        guard registry.connectedPeerIdentities.count < policy.maxConnectedPeers || registry.connection(for: handshake.identity) != nil else {
            connection.cancel()
            return nil
        }
        let direction = pending?.direction ?? NetworkPeerConnectionDirection.inbound
        let wasConnected = registry.connection(for: handshake.identity) != nil
        let isRegistered = registry.register(connection, for: handshake.identity, direction: direction)
        guard isRegistered else { return nil }

        removeConnectionIdentity(for: handshake.identity)
        connectionIdentities[identifier] = handshake.identity
        guard !wasConnected else { return nil }
        return .devicesChanged(peer: Peer(identity: handshake.identity, status: .connected))
    }

    fileprivate func rejectHandshake(from connection: Connection) {
        pendingConnections.removeValue(forKey: ObjectIdentifier(connection))?.timeout.cancel()
        connection.cancel()
    }

    fileprivate func expirePendingConnection(_ connection: Connection) {
        let identifier = ObjectIdentifier(connection)
        guard let pending = pendingConnections.removeValue(forKey: identifier) else { return }
        pending.timeout.cancel()
        pending.connection.cancel()
    }

    fileprivate func removeConnectionIdentity(for identity: PeerIdentity) {
        connectionIdentities = connectionIdentities.filter { $0.value != identity }
    }

    fileprivate func receiveData(_ data: Data, from connection: Connection) -> PeerSessionEvent? {
        guard let identity = connectionIdentities[ObjectIdentifier(connection)] else { return nil }
        return .didReceiveData(peer: Peer(identity: identity, status: .connected), data: data)
    }

    fileprivate func sendHandshake(on connection: Connection) {
        let handshake = PeerNetworkHandshake(identity: localPeer.identity)
        guard let payload = try? JSONEncoder().encode(handshake) else { return }
        connection.sendFrame(PeerNetworkFrame(kind: .handshake, payload: payload))
    }
}
