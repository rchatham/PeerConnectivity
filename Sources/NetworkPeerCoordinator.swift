//
//  NetworkPeerCoordinator.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

internal final class NetworkPeerCoordinator<Connection: NetworkPeerFrameSending> {

    fileprivate struct PendingConnection {
        internal let connection : Connection
        internal let direction : NetworkPeerConnectionDirection
    }

    fileprivate let localPeer : Peer
    fileprivate let registry : NetworkPeerConnectionRegistry<Connection>
    fileprivate let dataSender : NetworkPeerDataSender<Connection>
    fileprivate let queue = DispatchQueue(label: "PeerConnectivity.NetworkPeerCoordinator")
    fileprivate let sessionObserver : Observable<PeerSessionEvent>
    fileprivate let browserObserver : Observable<PeerBrowserEvent>
    fileprivate let advertiserObserver : Observable<PeerAdvertiserEvent>
    fileprivate var pendingConnections : [ObjectIdentifier:PendingConnection] = [:]
    fileprivate var connectionIdentities : [ObjectIdentifier:PeerIdentity] = [:]
    fileprivate var discoveredPeers : [PeerIdentity:Peer] = [:]

    internal init(localPeer: Peer,
        sessionObserver: Observable<PeerSessionEvent>,
        browserObserver: Observable<PeerBrowserEvent>,
        advertiserObserver: Observable<PeerAdvertiserEvent>) {
        self.localPeer = localPeer
        self.registry = NetworkPeerConnectionRegistry(localIdentity: localPeer.identity)
        self.dataSender = NetworkPeerDataSender(registry: registry)
        self.sessionObserver = sessionObserver
        self.browserObserver = browserObserver
        self.advertiserObserver = advertiserObserver
    }

    internal var connectedPeers : [Peer] {
        return queue.sync {
            registry.connectedPeerIdentities.map { Peer(identity: $0, status: .connected) }
        }
    }

    internal func addPendingConnection(_ connection: Connection, direction: NetworkPeerConnectionDirection) {
        queue.sync {
            pendingConnections[ObjectIdentifier(connection)] = PendingConnection(connection: connection, direction: direction)
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
            pendingConnections.removeValue(forKey: identifier)
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
            pendingConnections.values.forEach { $0.connection.cancel() }
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
            return .foundPeer(peer)
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
        pendingConnections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
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
