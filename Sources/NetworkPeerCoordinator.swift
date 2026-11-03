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
    /// Bounds the browser's endpoint table so hostile Bonjour traffic cannot grow it without limit.
    internal let maxDiscoveredPeers : Int
    /// TCP keepalive replaces an idle timeout: quiet peers stay connected, dead peers fail.
    internal let keepaliveIdle : Int
    internal let keepaliveInterval : Int
    internal let keepaliveCount : Int
    /// Upper bound on how long an invitation can hold a pending connection open.
    internal let maxInvitationTimeout : TimeInterval

    internal init(handshakeTimeout: TimeInterval = 10,
        maxPendingConnections: Int = 16,
        maxConnectedPeers: Int = 8,
        maxDiscoveredPeers: Int = 64,
        keepaliveIdle: Int = 30,
        keepaliveInterval: Int = 10,
        keepaliveCount: Int = 3,
        maxInvitationTimeout: TimeInterval = 120) {
        precondition(handshakeTimeout > 0, "PeerConnectivity: Network handshake timeout must be positive")
        precondition(maxPendingConnections > 0, "PeerConnectivity: Network pending connection limit must be positive")
        precondition(maxConnectedPeers > 0, "PeerConnectivity: Network connected peer limit must be positive")
        precondition(maxDiscoveredPeers > 0, "PeerConnectivity: Network discovered peer limit must be positive")
        precondition(keepaliveIdle > 0 && keepaliveInterval > 0 && keepaliveCount > 0,
            "PeerConnectivity: Network keepalive values must be positive")
        precondition(maxInvitationTimeout > 0, "PeerConnectivity: Network invitation timeout cap must be positive")
        self.handshakeTimeout = handshakeTimeout
        self.maxPendingConnections = maxPendingConnections
        self.maxConnectedPeers = maxConnectedPeers
        self.maxDiscoveredPeers = maxDiscoveredPeers
        self.keepaliveIdle = keepaliveIdle
        self.keepaliveInterval = keepaliveInterval
        self.keepaliveCount = keepaliveCount
        self.maxInvitationTimeout = maxInvitationTimeout
    }
}

internal final class NetworkPeerCoordinator<Connection: NetworkPeerFrameSending> {

    internal typealias HandshakeEncoder = (PeerNetworkHandshake) throws -> Data

    /// Registration waits for every local gate and the remote peer's `.admitted` frame, so
    /// neither side reports the other connected (or sends data) before both have decided.
    fileprivate struct PendingAdmission {
        internal let identity : PeerIdentity
        internal var isCertificateAccepted : Bool
        /// Outbound connections are the inviter, so only inbound ones wait for this gate.
        internal var isInvitationAccepted : Bool
        internal var hasReceivedInvitation = false
        internal var hasSentAdmission = false
        internal var isRemotelyAdmitted = false
    }

    fileprivate struct PendingConnection {
        internal let connection : Connection
        internal let direction : NetworkPeerConnectionDirection
        internal var timeout : DispatchWorkItem
    }

    fileprivate let localPeer : Peer
    fileprivate let registry : NetworkPeerConnectionRegistry<Connection>
    fileprivate let dataSender : NetworkPeerDataSender<Connection>
    fileprivate let queue = DispatchQueue(label: "PeerConnectivity.NetworkPeerCoordinator")
    fileprivate let sessionObserver : Observable<PeerSessionEvent>
    fileprivate let policy : NetworkPeerConnectionPolicy
    fileprivate let handshakeEncoder : HandshakeEncoder
    fileprivate let requiresCertificateDecision : Bool
    fileprivate var pendingConnections : [ObjectIdentifier:PendingConnection] = [:]
    fileprivate var connectionIdentities : [ObjectIdentifier:PeerIdentity] = [:]
    /// Handshaken connections held pending until both peers admit each other.
    fileprivate var pendingAdmissions : [ObjectIdentifier:PendingAdmission] = [:]

    internal init(localPeer: Peer,
        sessionObserver: Observable<PeerSessionEvent>,
        policy: NetworkPeerConnectionPolicy = NetworkPeerConnectionPolicy(),
        requiresCertificateDecision: Bool = false,
        handshakeEncoder: @escaping HandshakeEncoder = { try JSONEncoder().encode($0) }) {
        self.localPeer = localPeer
        self.registry = NetworkPeerConnectionRegistry(localIdentity: localPeer.identity)
        self.dataSender = NetworkPeerDataSender(registry: registry)
        self.sessionObserver = sessionObserver
        self.policy = policy
        self.requiresCertificateDecision = requiresCertificateDecision
        self.handshakeEncoder = handshakeEncoder
    }

    internal var connectedPeers : [Peer] {
        return queue.sync { connectedPeerSnapshot() }
    }

    /// Capture membership while the coordinator's mutation queue is held.
    fileprivate func connectedPeerSnapshot() -> [Peer] {
        return registry.connectedPeerIdentities.map { Peer(identity: $0, status: .connected) }
    }

    /**
     Tracks a new connection until both peers admit each other.

     - parameter invitation: Sent after the handshake on outbound connections. Its timeout,
       clamped to the policy, bounds how long the connection may stay pending.
     */
    internal func addPendingConnection(_ connection: Connection,
        direction: NetworkPeerConnectionDirection,
        invitation: PeerNetworkInvitation? = nil) {
        queue.sync {
            let identifier = ObjectIdentifier(connection)
            guard registry.connectedPeerIdentities.count < policy.maxConnectedPeers,
                pendingConnections.count < policy.maxPendingConnections,
                pendingConnections[identifier] == nil,
                connectionIdentities[identifier] == nil else {
                connection.cancel()
                return
            }
            let outboundInvitation = direction == .outbound
                ? clampedInvitation(invitation ?? PeerNetworkInvitation(timeout: policy.handshakeTimeout))
                : nil
            pendingConnections[identifier] = PendingConnection(connection: connection,
                direction: direction,
                timeout: scheduleExpiration(of: connection,
                    after: outboundInvitation?.timeout ?? policy.handshakeTimeout))
            sendHandshake(on: connection)
            if let outboundInvitation = outboundInvitation, pendingConnections[identifier] != nil {
                sendInvitation(outboundInvitation, on: connection)
            }
        }
    }

    internal func receiveFrame(_ frame: PeerNetworkFrame, from connection: Connection) {
        let event : PeerSessionEvent? = queue.sync {
            switch frame.kind {
            case .handshake:
                return receiveHandshake(frame.payload, from: connection)
            case .data:
                return receiveData(frame.payload, from: connection)
            case .admitted:
                return receiveAdmitted(from: connection)
            case .invitation:
                return receiveInvitation(frame.payload, from: connection)
            case .declined:
                rejectProtocolPeer(connection)
                return nil
            }
        }
        guard let event = event else { return }
        sessionObserver.update(event)
    }

    internal func sendData(_ data: Data, toPeers peers: [Peer] = []) {
        queue.sync {
            dataSender.sendData(data, toPeers: peers.map { $0.identity })
        }
    }

    internal func sendData(_ data: Data, toPeers peers: [Peer], completion: @escaping ([Peer:Error]) -> Void) {
        queue.sync {
            dataSender.sendData(data, toPeers: peers.map { $0.identity }) { failures in
                completion(Dictionary(failures.map { (Peer(identity: $0.key, status: .notConnected), $0.value) },
                    uniquingKeysWith: { first, _ in first }))
            }
        }
    }

    internal func removeConnection(_ connection: Connection) {
        var connectionToCancel : Connection?
        let event : PeerSessionEvent? = queue.sync {
            let identifier = ObjectIdentifier(connection)
            pendingAdmissions.removeValue(forKey: identifier)
            if let pending = pendingConnections.removeValue(forKey: identifier) {
                pending.timeout.cancel()
                connectionToCancel = pending.connection
            }
            guard let identity = connectionIdentities.removeValue(forKey: identifier) else { return nil }
            guard registry.connection(for: identity) === connection else { return nil }
            registry.remove(identity: identity)
            connectionToCancel = connection
            return .devicesChanged(peer: Peer(identity: identity, status: .notConnected),
                connectedPeers: connectedPeerSnapshot())
        }
        connectionToCancel?.cancel()
        guard let event = event else { return }
        sessionObserver.update(event)
    }

    internal func cancelAllConnections() {
        queue.sync {
            pendingConnections.values.forEach {
                $0.timeout.cancel()
                $0.connection.cancel()
            }
            pendingConnections.removeAll()
            pendingAdmissions.removeAll()
            connectionIdentities.removeAll()
            registry.cancelAll()
        }
    }

    fileprivate func receiveHandshake(_ data: Data, from connection: Connection) -> PeerSessionEvent? {
        guard let handshake = try? JSONDecoder().decode(PeerNetworkHandshake.self, from: data),
            handshake.protocolVersion == PeerNetworkHandshake.currentProtocolVersion else {
            rejectHandshake(from: connection)
            return nil
        }

        guard PeerIdentity.isValidIdentifier(handshake.identity.identifier),
            Peer.isValidDisplayName(handshake.identity.displayName),
            handshake.identity != localPeer.identity else {
            rejectHandshake(from: connection)
            return nil
        }

        let identifier = ObjectIdentifier(connection)
        if let registeredIdentity = connectionIdentities[identifier] {
            guard registeredIdentity != handshake.identity else { return nil }
            connectionIdentities.removeValue(forKey: identifier)
            guard registry.connection(for: registeredIdentity) === connection else {
                connection.cancel()
                return nil
            }
            registry.remove(identity: registeredIdentity)
            connection.cancel()
            return .devicesChanged(peer: Peer(identity: registeredIdentity, status: .notConnected),
                connectedPeers: connectedPeerSnapshot())
        }
        guard pendingAdmissions[identifier] == nil else {
            // A second handshake while admission is pending is a protocol violation.
            rejectHandshake(from: connection)
            return nil
        }
        guard let pending = pendingConnections[identifier] else {
            connection.cancel()
            return nil
        }
        pendingAdmissions[identifier] = PendingAdmission(identity: handshake.identity,
            isCertificateAccepted: !requiresCertificateDecision,
            isInvitationAccepted: pending.direction == .outbound)
        guard requiresCertificateDecision else {
            return admitIfLocallyAccepted(connection)
        }
        return .didReceiveCertificate(peer: Peer(identity: handshake.identity, status: .notConnected),
            certificate: connection.peerCertificateChain,
            handler: decisionHandler(for: connection) { coordinator, connection, accept in
                coordinator.completeCertificateDecision(accept, for: connection)
            })
    }

    fileprivate func receiveInvitation(_ data: Data, from connection: Connection) -> PeerSessionEvent? {
        let identifier = ObjectIdentifier(connection)
        guard var admission = pendingAdmissions[identifier],
            var pending = pendingConnections[identifier],
            pending.direction == .inbound,
            !admission.hasReceivedInvitation,
            let invitation = try? JSONDecoder().decode(PeerNetworkInvitation.self, from: data),
            invitation.isValid else {
            // Invitations before the handshake, on outbound connections, repeated, or malformed.
            rejectProtocolPeer(connection)
            return nil
        }
        admission.hasReceivedInvitation = true
        pendingAdmissions[identifier] = admission
        pending.timeout.cancel()
        pending.timeout = scheduleExpiration(of: connection, after: clampedInvitation(invitation).timeout)
        pendingConnections[identifier] = pending
        return .didReceiveInvitation(peer: Peer(identity: admission.identity, status: .notConnected),
            context: invitation.context,
            handler: decisionHandler(for: connection) { coordinator, connection, accept in
                coordinator.completeInvitationDecision(accept, for: connection)
            })
    }

    /// Wraps a local decision so it runs once on the coordinator queue; late or repeated
    /// decisions find no matching admission and are ignored.
    fileprivate func decisionHandler(for connection: Connection,
        apply: @escaping (NetworkPeerCoordinator, Connection, Bool) -> PeerSessionEvent?) -> (Bool) -> Void {
        return { [weak self, weak connection] accept in
            guard let self = self, let connection = connection else { return }
            self.queue.async {
                guard let event = apply(self, connection, accept) else { return }
                self.sessionObserver.update(event)
            }
        }
    }

    fileprivate func completeCertificateDecision(_ accept: Bool, for connection: Connection) -> PeerSessionEvent? {
        let identifier = ObjectIdentifier(connection)
        guard var admission = pendingAdmissions[identifier], !admission.isCertificateAccepted else { return nil }
        guard accept else {
            decline(connection)
            return nil
        }
        admission.isCertificateAccepted = true
        pendingAdmissions[identifier] = admission
        return admitIfLocallyAccepted(connection)
    }

    fileprivate func completeInvitationDecision(_ accept: Bool, for connection: Connection) -> PeerSessionEvent? {
        let identifier = ObjectIdentifier(connection)
        guard var admission = pendingAdmissions[identifier],
            admission.hasReceivedInvitation,
            !admission.isInvitationAccepted else { return nil }
        guard accept else {
            decline(connection)
            return nil
        }
        admission.isInvitationAccepted = true
        pendingAdmissions[identifier] = admission
        return admitIfLocallyAccepted(connection)
    }

    fileprivate func admitIfLocallyAccepted(_ connection: Connection) -> PeerSessionEvent? {
        let identifier = ObjectIdentifier(connection)
        guard var admission = pendingAdmissions[identifier],
            admission.isCertificateAccepted,
            admission.isInvitationAccepted,
            !admission.hasSentAdmission else { return nil }
        admission.hasSentAdmission = true
        pendingAdmissions[identifier] = admission
        connection.sendFrame(PeerNetworkFrame(kind: .admitted, payload: Data()))
        return registerIfAdmitted(connection)
    }

    fileprivate func receiveAdmitted(from connection: Connection) -> PeerSessionEvent? {
        let identifier = ObjectIdentifier(connection)
        guard var admission = pendingAdmissions[identifier], !admission.isRemotelyAdmitted else {
            // Unsolicited or repeated admission is a protocol violation.
            rejectProtocolPeer(connection)
            return nil
        }
        admission.isRemotelyAdmitted = true
        pendingAdmissions[identifier] = admission
        return registerIfAdmitted(connection)
    }

    fileprivate func registerIfAdmitted(_ connection: Connection) -> PeerSessionEvent? {
        let identifier = ObjectIdentifier(connection)
        guard let admission = pendingAdmissions[identifier],
            admission.hasSentAdmission, admission.isRemotelyAdmitted else { return nil }
        pendingAdmissions.removeValue(forKey: identifier)
        guard let pending = pendingConnections.removeValue(forKey: identifier) else { return nil }
        return register(admission.identity, connection: connection, pending: pending)
    }

    fileprivate func register(_ identity: PeerIdentity,
        connection: Connection,
        pending: PendingConnection) -> PeerSessionEvent? {
        pending.timeout.cancel()
        guard registry.connectedPeerIdentities.count < policy.maxConnectedPeers || registry.connection(for: identity) != nil else {
            connection.cancel()
            return nil
        }
        let wasConnected = registry.connection(for: identity) != nil
        let isRegistered = registry.register(connection, for: identity, direction: pending.direction)
        guard isRegistered else { return nil }

        removeConnectionIdentity(for: identity)
        connectionIdentities[ObjectIdentifier(connection)] = identity
        guard !wasConnected else { return nil }
        return .devicesChanged(peer: Peer(identity: identity, status: .connected),
            connectedPeers: connectedPeerSnapshot())
    }

    fileprivate func rejectHandshake(from connection: Connection) {
        let identifier = ObjectIdentifier(connection)
        pendingAdmissions.removeValue(forKey: identifier)
        guard let pending = pendingConnections.removeValue(forKey: identifier) else { return }
        pending.timeout.cancel()
        pending.connection.cancel()
    }

    /// Cancels a peer that broke the admission protocol, whether pending or registered.
    fileprivate func rejectProtocolPeer(_ connection: Connection) {
        rejectHandshake(from: connection)
        connection.cancel()
    }

    /// Tells the remote peer it was declined, then closes once the frame is processed.
    fileprivate func decline(_ connection: Connection) {
        let identifier = ObjectIdentifier(connection)
        pendingAdmissions.removeValue(forKey: identifier)
        guard let pending = pendingConnections.removeValue(forKey: identifier) else { return }
        pending.timeout.cancel()
        pending.connection.sendFrame(PeerNetworkFrame(kind: .declined, payload: Data())) { _ in
            pending.connection.cancel()
        }
    }

    fileprivate func scheduleExpiration(of connection: Connection, after interval: TimeInterval) -> DispatchWorkItem {
        let timeout = DispatchWorkItem { [weak self, weak connection] in
            guard let connection = connection else { return }
            self?.expirePendingConnection(connection)
        }
        queue.asyncAfter(deadline: .now() + interval, execute: timeout)
        return timeout
    }

    fileprivate func clampedInvitation(_ invitation: PeerNetworkInvitation) -> PeerNetworkInvitation {
        let timeout = invitation.timeout.isFinite && invitation.timeout > 0 ? invitation.timeout : policy.handshakeTimeout
        return PeerNetworkInvitation(context: invitation.context,
            timeout: min(timeout, policy.maxInvitationTimeout))
    }

    fileprivate func expirePendingConnection(_ connection: Connection) {
        let identifier = ObjectIdentifier(connection)
        pendingAdmissions.removeValue(forKey: identifier)
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

    fileprivate func sendInvitation(_ invitation: PeerNetworkInvitation, on connection: Connection) {
        guard invitation.isValid, let payload = try? JSONEncoder().encode(invitation) else {
            NSLog("%@", "PeerConnectivity: Invalid Network invitation; canceling connection")
            rejectHandshake(from: connection)
            return
        }
        connection.sendFrame(PeerNetworkFrame(kind: .invitation, payload: payload))
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
