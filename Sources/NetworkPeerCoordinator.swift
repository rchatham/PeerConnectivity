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
        return registry.connectedPeerIdentities.map { Peer(identity: $0, status: .connected) }
    }

    internal func addPendingConnection(_ connection: Connection, direction: NetworkPeerConnectionDirection) {
        pendingConnections[ObjectIdentifier(connection)] = PendingConnection(connection: connection, direction: direction)
        sendHandshake(on: connection)
    }

    internal func receiveFrame(_ frame: PeerNetworkFrame, from connection: Connection) {
        switch frame.kind {
        case .handshake:
            receiveHandshake(frame.payload, from: connection)
        case .data:
            receiveData(frame.payload, from: connection)
        }
    }

    internal func sendData(_ data: Data, toPeers peers: [Peer] = []) {
        dataSender.sendData(data, toPeers: peers.map { $0.identity })
    }

    internal func removeConnection(_ connection: Connection) {
        let identifier = ObjectIdentifier(connection)
        pendingConnections.removeValue(forKey: identifier)
        guard let identity = connectionIdentities.removeValue(forKey: identifier) else { return }
        guard registry.connection(for: identity) === connection else { return }
        registry.remove(identity: identity)
        sessionObserver.value = .devicesChanged(peer: Peer(identity: identity, status: .notConnected))
    }

    internal func cancelAllConnections() {
        pendingConnections.values.forEach { $0.connection.cancel() }
        pendingConnections.removeAll()
        connectionIdentities.removeAll()
        registry.cancelAll()
    }

    internal func foundPeer(identity: PeerIdentity) {
        let peer = Peer(identity: identity, status: .notConnected)
        discoveredPeers[identity] = peer
        browserObserver.value = .foundPeer(peer)
    }

    internal func lostPeer(identity: PeerIdentity) {
        let peer = discoveredPeers.removeValue(forKey: identity) ?? Peer(identity: identity, status: .notConnected)
        browserObserver.value = .lostPeer(peer)
    }

    fileprivate func receiveHandshake(_ data: Data, from connection: Connection) {
        guard let handshake = try? JSONDecoder().decode(PeerNetworkHandshake.self, from: data),
            handshake.protocolVersion == PeerNetworkHandshake.currentProtocolVersion else {
            rejectHandshake(from: connection)
            return
        }

        let identifier = ObjectIdentifier(connection)
        let pending = pendingConnections.removeValue(forKey: identifier)
        let direction = pending?.direction ?? NetworkPeerConnectionDirection.inbound
        let isRegistered = registry.register(connection, for: handshake.identity, direction: direction)
        guard isRegistered else { return }

        connectionIdentities[identifier] = handshake.identity
        sessionObserver.value = .devicesChanged(peer: Peer(identity: handshake.identity, status: .connected))
    }

    fileprivate func rejectHandshake(from connection: Connection) {
        pendingConnections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }

    fileprivate func receiveData(_ data: Data, from connection: Connection) {
        guard let identity = connectionIdentities[ObjectIdentifier(connection)] else { return }
        sessionObserver.value = .didReceiveData(peer: Peer(identity: identity, status: .connected), data: data)
    }

    fileprivate func sendHandshake(on connection: Connection) {
        let handshake = PeerNetworkHandshake(identity: localPeer.identity)
        guard let payload = try? JSONEncoder().encode(handshake) else { return }
        connection.sendFrame(PeerNetworkFrame(kind: .handshake, payload: payload))
    }
}
