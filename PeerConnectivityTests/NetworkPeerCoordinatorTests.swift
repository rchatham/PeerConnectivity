//
//  NetworkPeerCoordinatorTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import XCTest
@testable import PeerConnectivity

private enum CoordinatorHandshakeEncodingError : Error {
    case failed
}

private final class MockCoordinatorConnection : NetworkPeerFrameSending {
    internal private(set) var sentFrames : [PeerNetworkFrame] = []
    internal var peerCertificateChain : [Any]?
    internal private(set) var cancelCallCount = 0

    internal func sendFrame(_ frame: PeerNetworkFrame, onProcessed: @escaping (Error?) -> Void) {
        sentFrames.append(frame)
        onProcessed(nil)
    }

    internal func cancel() {
        cancelCallCount += 1
    }

    internal func clearSentFrames() {
        sentFrames.removeAll()
    }
}

final class NetworkPeerCoordinatorTests : XCTestCase {

    internal func testPendingConnectionSendsLocalHandshake() async throws {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(connection, direction: .outbound)

        XCTAssertEqual(connection.sentFrames.map { $0.kind }, [.handshake, .invitation],
            "Outbound connections invite the remote peer right after the handshake")
        let payload = try XCTUnwrap(connection.sentFrames.first?.payload)
        let handshake = try JSONDecoder().decode(PeerNetworkHandshake.self, from: payload)
        XCTAssertEqual(handshake.identity, harness.localPeer.identity)
    }

    internal func testGeneratedNetworkPeersCompleteHandshakeWithoutChangingLegacyIdentity() async throws {
        let firstPeer = Peer(networkDisplayName: "First Peer")
        let secondPeer = Peer(networkDisplayName: "Second Peer")
        let first = Harness(localPeer: firstPeer)
        let second = Harness(localPeer: secondPeer)
        await first.observeEvents()
        await second.observeEvents()
        let firstConnection = MockCoordinatorConnection()
        let secondConnection = MockCoordinatorConnection()

        first.coordinator.addPendingConnection(firstConnection, direction: .outbound)
        second.coordinator.addPendingConnection(secondConnection, direction: .inbound)
        await exchangeFrames(first, firstConnection, second, secondConnection)

        XCTAssertTrue(PeerIdentity.isValidIdentifier(firstPeer.identity.identifier))
        XCTAssertTrue(PeerIdentity.isValidIdentifier(secondPeer.identity.identifier))
        XCTAssertEqual(first.coordinator.connectedPeers.map { $0.identity }, [secondPeer.identity])
        XCTAssertEqual(second.coordinator.connectedPeers.map { $0.identity }, [firstPeer.identity])
        XCTAssertEqual(firstConnection.cancelCallCount, 0)
        XCTAssertEqual(secondConnection.cancelCallCount, 0)
        XCTAssertFalse(PeerIdentity.isValidIdentifier(Peer(displayName: "Legacy Peer").identity.identifier))
    }

    internal func testHandshakeEncodingFailureImmediatelyRejectsPendingConnectionOnce() async {
        let harness = await makeHarness(handshakeEncoder: { _ in
            throw CoordinatorHandshakeEncodingError.failed
        })
        let connection = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.removeConnection(connection)
        harness.coordinator.cancelAllConnections()

        XCTAssertTrue(connection.sentFrames.isEmpty)
        XCTAssertEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
    }

    internal func testHandshakeRegistersConnectedPeerAndEmitsSessionEvent() async throws {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()
        let remoteIdentity = identity("remote")

        let expectation = expectSessionEvent(in: harness) { event in
            guard let peer = self.devicesChangedPeer(from: event) else { return false }
            return peer == Peer(identity: remoteIdentity, status: .connected)
        }

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        connect(remoteIdentity, on: connection, in: harness)
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(harness.coordinator.connectedPeers, [Peer(identity: remoteIdentity, status: .connected)])
        let peer = try XCTUnwrap(devicesChangedPeer(from: harness.sessionEvents.last))
        XCTAssertEqual(peer, Peer(identity: remoteIdentity, status: .connected))
        XCTAssertEqual(peer.status, .connected)
    }

    internal func testRapidConnectionChangesPreserveEventTimePeerSnapshots() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()
        let remoteIdentity = identity("remote")

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        connect(remoteIdentity, on: connection, in: harness)
        harness.coordinator.removeConnection(connection)
        await harness.sessionObserver.flush()

        let snapshots = harness.sessionEvents.compactMap { event -> [Peer]? in
            guard case .devicesChanged(_, connectedPeers: let peers) = event else { return nil }
            return peers
        }
        XCTAssertEqual(snapshots, [[Peer(identity: remoteIdentity, status: .connected)], []])
    }

    internal func testRepeatedHandshakeForSameIdentityPreservesConnection() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()
        let remoteIdentity = identity("remote")
        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        connect(remoteIdentity, on: connection, in: harness)
        await harness.sessionObserver.flush()
        let eventCount = harness.sessionEvents.count

        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
        await harness.sessionObserver.flush()

        XCTAssertEqual(connection.cancelCallCount, 0)
        XCTAssertEqual(harness.coordinator.connectedPeers.map { $0.identity }, [remoteIdentity])
        XCTAssertEqual(harness.sessionEvents.count, eventCount)
    }

    internal func testRepeatedHandshakeForDifferentIdentityRemovesOriginalPeer() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()
        let original = identity("remote")
        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        connect(original, on: connection, in: harness)

        harness.coordinator.receiveFrame(handshakeFrame(identity("impostor")), from: connection)
        await harness.sessionObserver.flush()

        XCTAssertEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
        XCTAssertEqual(harness.sessionEvents.compactMap { devicesChangedPeer(from: $0) }.map { $0.status },
            [.connected, .notConnected])
    }

    internal func testDataFrameEmitsSessionDataEventForRegisteredPeer() async throws {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()
        let remoteIdentity = identity("remote")
        let payload = Data([1, 2, 3])

        let expectation = expectSessionEvent(in: harness) { event in
            guard let received = self.receivedData(from: event) else { return false }
            return received.peer == Peer(identity: remoteIdentity, status: .connected) && received.data == payload
        }

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        connect(remoteIdentity, on: connection, in: harness)
        harness.coordinator.receiveFrame(PeerNetworkFrame(kind: .data, payload: payload), from: connection)
        await fulfillment(of: [expectation], timeout: 1)

        let received = try XCTUnwrap(harness.sessionEvents.reversed().compactMap { receivedData(from: $0) }.first)
        XCTAssertEqual(received.peer, Peer(identity: remoteIdentity, status: .connected))
        XCTAssertEqual(received.data, payload)
    }

    internal func testSendDataUsesRegisteredPeerConnections() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()
        let remoteIdentity = identity("remote")
        let payload = Data([4, 5, 6])

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        connect(remoteIdentity, on: connection, in: harness)
        connection.clearSentFrames()
        harness.coordinator.sendData(payload)

        XCTAssertEqual(connection.sentFrames, [PeerNetworkFrame(kind: .data, payload: payload)])
    }

    internal func testRemoveConnectionEmitsNotConnectedEvent() async throws {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()
        let remoteIdentity = identity("remote")

        let expectation = expectSessionEvent(in: harness) { event in
            guard let peer = self.devicesChangedPeer(from: event) else { return false }
            return peer == Peer(identity: remoteIdentity, status: .notConnected)
        }

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        connect(remoteIdentity, on: connection, in: harness)
        harness.coordinator.removeConnection(connection)
        harness.coordinator.removeConnection(connection)
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
        let disconnectedPeers = harness.sessionEvents.compactMap { devicesChangedPeer(from: $0) }
            .filter { $0.status == .notConnected }
        let peer = try XCTUnwrap(disconnectedPeers.first)
        XCTAssertEqual(disconnectedPeers.count, 1)
        XCTAssertEqual(peer, Peer(identity: remoteIdentity, status: .notConnected))
        XCTAssertEqual(peer.status, .notConnected)
    }

    internal func testRemovePendingConnectionCancelsWithoutSessionEvent() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        let sessionEventCount = harness.sessionEvents.count
        harness.coordinator.removeConnection(connection)

        XCTAssertEqual(connection.cancelCallCount, 1)
        XCTAssertEqual(harness.sessionEvents.count, sessionEventCount)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
    }

    internal func testRemovingDuplicateLoserDoesNotRemoveWinningConnection() async throws {
        let harness = await makeHarness(localIdentifier: "zlocal")
        let outbound = MockCoordinatorConnection()
        let inbound = MockCoordinatorConnection()
        let remoteIdentity = identity("remote")

        let connectedExpectation = expectSessionEvent(in: harness) { event in
            guard let peer = self.devicesChangedPeer(from: event) else { return false }
            return peer == Peer(identity: remoteIdentity, status: .connected)
        }

        harness.coordinator.addPendingConnection(outbound, direction: .outbound)
        connect(remoteIdentity, on: outbound, in: harness)
        await fulfillment(of: [connectedExpectation], timeout: 1)
        let deviceEventCount = harness.sessionEvents.compactMap { devicesChangedPeer(from: $0) }.count
        harness.coordinator.addPendingConnection(inbound, direction: .inbound)
        await connectInbound(remoteIdentity, on: inbound, in: harness)
        harness.coordinator.removeConnection(outbound)

        await harness.sessionObserver.flush()
        XCTAssertEqual(outbound.cancelCallCount, 1)
        XCTAssertEqual(harness.sessionEvents.compactMap { devicesChangedPeer(from: $0) }.count, deviceEventCount)
        XCTAssertEqual(harness.coordinator.connectedPeers, [Peer(identity: remoteIdentity, status: .connected)])

        let disconnectedExpectation = expectSessionEvent(in: harness) { event in
            guard let peer = self.devicesChangedPeer(from: event) else { return false }
            return peer == Peer(identity: remoteIdentity, status: .notConnected)
        }

        harness.coordinator.removeConnection(inbound)
        await fulfillment(of: [disconnectedExpectation], timeout: 1)

        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
        let peer = try XCTUnwrap(harness.sessionEvents.compactMap { devicesChangedPeer(from: $0) }
            .first { $0.status == .notConnected })
        XCTAssertEqual(peer, Peer(identity: remoteIdentity, status: .notConnected))
    }

    internal func testCancelAllConnectionsCancelsPendingAndRegisteredConnections() async {
        let harness = await makeHarness()
        let pending = MockCoordinatorConnection()
        let registered = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(pending, direction: .outbound)
        harness.coordinator.addPendingConnection(registered, direction: .outbound)
        connect(identity("remote"), on: registered, in: harness)
        harness.coordinator.cancelAllConnections()

        XCTAssertEqual(pending.cancelCallCount, 1)
        XCTAssertEqual(registered.cancelCallCount, 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
    }

    internal func testHandshakeTimeoutCancelsPendingConnection() {
        let harness = Harness(localPeer: Peer(identity: identity("local"), status: .currentUser),
            policy: NetworkPeerConnectionPolicy(handshakeTimeout: 0.01))
        let connection = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
    }

    internal func testPendingConnectionLimitCancelsExcessConnection() async {
        let harness = await makeHarness(policy: NetworkPeerConnectionPolicy(maxPendingConnections: 1))
        let first = MockCoordinatorConnection()
        let second = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(first, direction: .outbound)
        harness.coordinator.addPendingConnection(second, direction: .outbound)

        XCTAssertEqual(first.cancelCallCount, 0)
        XCTAssertEqual(second.cancelCallCount, 1)
    }

    internal func testConnectedPeerLimitCancelsExcessConnection() async {
        let harness = await makeHarness(policy: NetworkPeerConnectionPolicy(maxConnectedPeers: 1))
        let first = MockCoordinatorConnection()
        let second = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(first, direction: .outbound)
        connect(identity("first"), on: first, in: harness)
        harness.coordinator.addPendingConnection(second, direction: .outbound)

        XCTAssertEqual(second.cancelCallCount, 1)
        XCTAssertEqual(harness.coordinator.connectedPeers, [Peer(identity: identity("first"), status: .connected)])
    }

    internal func testConnectedPeerLimitRejectsHandshakeWhenLimitReached() async {
        let harness = await makeHarness(policy: NetworkPeerConnectionPolicy(maxPendingConnections: 2, maxConnectedPeers: 1))
        let first = MockCoordinatorConnection()
        let second = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(first, direction: .outbound)
        harness.coordinator.addPendingConnection(second, direction: .outbound)
        connect(identity("first"), on: first, in: harness)
        connect(identity("second"), on: second, in: harness)

        XCTAssertEqual(second.cancelCallCount, 1)
        XCTAssertEqual(harness.coordinator.connectedPeers, [Peer(identity: identity("first"), status: .connected)])
    }

    internal func testInvalidHandshakeCancelsPendingConnection() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(PeerNetworkFrame(kind: .handshake, payload: Data([1, 2, 3])), from: connection)

        XCTAssertEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
    }

    internal func testUnsupportedHandshakeVersionCancelsPendingConnection() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(handshakeFrame(identity("remote"), protocolVersion: 999), from: connection)

        XCTAssertEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
    }

    internal func testHandshakeWithEmptyDisplayNameIsRejectedOnce() async {
        await assertRejectedHandshake(displayName: "")
    }

    internal func testHandshakeWith64ByteASCIINameIsRejectedOnce() async {
        await assertRejectedHandshake(displayName: String(repeating: "a", count: 64))
    }

    internal func testHandshakeWithMultibyteNameOver63BytesIsRejectedOnce() async {
        await assertRejectedHandshake(displayName: String(repeating: "🙂", count: 16))
    }

    internal func testHandshakeWith63ByteDisplayNameRegistersAndEmitsEvent() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()
        let displayName = String(repeating: "a", count: 63)
        let remoteIdentity = PeerIdentity(identifier: "remote", displayName: displayName)
        let expectation = expectSessionEvent(in: harness) { event in
            self.devicesChangedPeer(from: event)?.identity == remoteIdentity
        }

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        connect(remoteIdentity, on: connection, in: harness)
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(connection.cancelCallCount, 0)
        XCTAssertEqual(harness.coordinator.connectedPeers.map { $0.identity }, [remoteIdentity])
        XCTAssertEqual(harness.sessionEvents.compactMap { devicesChangedPeer(from: $0) }.count, 1)
    }

    internal func testHandshakeWithExactBoundaryIdentifierRegistersAndEmitsEvent() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()
        let identifier = String(repeating: "🙂", count: 45)
        let remoteIdentity = PeerIdentity(identifier: identifier, displayName: "Remote")
        let expectation = expectSessionEvent(in: harness) { event in
            self.devicesChangedPeer(from: event)?.identity == remoteIdentity
        }

        XCTAssertEqual(identifier.utf8.count, PeerIdentity.maxIdentifierByteLength)
        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        connect(remoteIdentity, on: connection, in: harness)
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(connection.cancelCallCount, 0)
        XCTAssertEqual(harness.coordinator.connectedPeers.map { $0.identity }, [remoteIdentity])
        XCTAssertEqual(harness.sessionEvents.compactMap { devicesChangedPeer(from: $0) }.count, 1)
    }

    internal func testHandshakeWithOversizedASCIIIdentifierIsRejectedOnce() async {
        await assertRejectedHandshake(identifier: String(repeating: "a", count: 181))
    }

    internal func testHandshakeWithOversizedMultibyteIdentifierIsRejectedOnce() async {
        await assertRejectedHandshake(identifier: String(repeating: "🙂", count: 46))
    }

    internal func testHandshakeWithEmptyIdentifierIsRejectedOnce() async {
        await assertRejectedHandshake(identifier: "")
    }

    internal func testSelfHandshakeCancelsPendingConnection() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(handshakeFrame(harness.localPeer.identity), from: connection)

        XCTAssertEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
    }

    internal func testDuplicateIdentityCannotSpoofRegisteredConnection() async {
        let harness = await makeHarness(localIdentifier: "alocal")
        let registered = MockCoordinatorConnection()
        let duplicate = MockCoordinatorConnection()
        let remoteIdentity = identity("remote")
        let payload = Data([9, 8, 7])

        harness.coordinator.addPendingConnection(registered, direction: .outbound)
        connect(remoteIdentity, on: registered, in: harness)
        registered.clearSentFrames()
        harness.coordinator.addPendingConnection(duplicate, direction: .inbound)
        await connectInbound(remoteIdentity, on: duplicate, in: harness)
        duplicate.clearSentFrames()
        harness.coordinator.sendData(payload)

        XCTAssertEqual(duplicate.cancelCallCount, 1)
        XCTAssertEqual(duplicate.sentFrames, [])
        XCTAssertEqual(registered.sentFrames, [PeerNetworkFrame(kind: .data, payload: payload)])
        XCTAssertEqual(harness.coordinator.connectedPeers, [Peer(identity: remoteIdentity, status: .connected)])
    }

    private func assertRejectedHandshake(identifier: String) async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()
        let remoteIdentity = PeerIdentity(identifier: identifier, displayName: "Remote")
        let frame = handshakeFrame(remoteIdentity)

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(frame, from: connection)
        harness.coordinator.receiveFrame(frame, from: connection)
        harness.coordinator.removeConnection(connection)
        harness.coordinator.cancelAllConnections()

        XCTAssertEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
        XCTAssertTrue(harness.sessionEvents.compactMap { devicesChangedPeer(from: $0) }.isEmpty)
    }

    private func assertRejectedHandshake(displayName: String) async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()
        let remoteIdentity = PeerIdentity(identifier: "remote", displayName: displayName)
        let frame = handshakeFrame(remoteIdentity)

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(frame, from: connection)
        harness.coordinator.receiveFrame(frame, from: connection)
        harness.coordinator.removeConnection(connection)
        harness.coordinator.cancelAllConnections()

        XCTAssertEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
        XCTAssertTrue(harness.sessionEvents.compactMap { devicesChangedPeer(from: $0) }.isEmpty)
    }

    // MARK: Certificate admission

    internal func testCertificateModeHoldsPeerUntilBothSidesAdmit() async throws {
        let harness = await makeHarness(requiresCertificateDecision: true)
        let connection = MockCoordinatorConnection()
        connection.peerCertificateChain = ["leaf", "issuer"]
        let remoteIdentity = identity("remote")
        let certificateEvent = expectSessionEvent(in: harness) { self.certificateRequest(from: $0) != nil }
        let connectedEvent = expectSessionEvent(in: harness) { self.devicesChangedPeer(from: $0)?.status == .connected }

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
        await fulfillment(of: [certificateEvent], timeout: 1)
        let request = try XCTUnwrap(harness.sessionEvents.compactMap { certificateRequest(from: $0) }.first)

        XCTAssertEqual(request.peer.identity, remoteIdentity)
        XCTAssertEqual(request.certificate as? [String], ["leaf", "issuer"])
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty, "Peers must not connect before the certificate decision")

        request.handler(true)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty, "Peers must not connect before the remote admits them")
        XCTAssertEqual(connection.sentFrames.last?.kind, .admitted)

        harness.coordinator.receiveFrame(PeerNetworkFrame(kind: .admitted, payload: Data()), from: connection)
        await fulfillment(of: [connectedEvent], timeout: 1)
        XCTAssertEqual(harness.coordinator.connectedPeers.map { $0.identity }, [remoteIdentity])
        XCTAssertEqual(connection.cancelCallCount, 0)
    }

    internal func testCertificateModeDropsDataAndAcceptsRemoteAdmissionBeforeLocalDecision() async throws {
        let harness = await makeHarness(requiresCertificateDecision: true)
        let connection = MockCoordinatorConnection()
        let remoteIdentity = identity("remote")
        let certificateEvent = expectSessionEvent(in: harness) { self.certificateRequest(from: $0) != nil }
        let connectedEvent = expectSessionEvent(in: harness) { self.devicesChangedPeer(from: $0)?.status == .connected }

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
        harness.coordinator.receiveFrame(PeerNetworkFrame(kind: .data, payload: Data([1])), from: connection)
        harness.coordinator.receiveFrame(PeerNetworkFrame(kind: .admitted, payload: Data()), from: connection)
        await fulfillment(of: [certificateEvent], timeout: 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)

        try XCTUnwrap(harness.sessionEvents.compactMap { certificateRequest(from: $0) }.first).handler(true)
        await fulfillment(of: [connectedEvent], timeout: 1)

        XCTAssertEqual(harness.coordinator.connectedPeers.map { $0.identity }, [remoteIdentity])
        XCTAssertTrue(harness.sessionEvents.compactMap { receivedData(from: $0) }.isEmpty,
            "Data from a peer that is not yet admitted must not be delivered")
    }

    internal func testCertificateRejectionCancelsAndIgnoresLateDecisions() async throws {
        let harness = await makeHarness(requiresCertificateDecision: true)
        let connection = MockCoordinatorConnection()
        let certificateEvent = expectSessionEvent(in: harness) { self.certificateRequest(from: $0) != nil }

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(handshakeFrame(identity("remote")), from: connection)
        await fulfillment(of: [certificateEvent], timeout: 1)
        let request = try XCTUnwrap(harness.sessionEvents.compactMap { certificateRequest(from: $0) }.first)

        request.handler(false)
        request.handler(true)
        harness.coordinator.receiveFrame(PeerNetworkFrame(kind: .admitted, payload: Data()), from: connection)

        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
        XCTAssertFalse(connection.sentFrames.contains { $0.kind == .admitted }, "Rejected peers must not be admitted")
        XCTAssertGreaterThanOrEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.sessionEvents.compactMap { devicesChangedPeer(from: $0) }.isEmpty)
    }

    internal func testCertificateDecisionAfterHandshakeTimeoutIsIgnored() async throws {
        let harness = await makeHarness(policy: NetworkPeerConnectionPolicy(handshakeTimeout: 0.05),
            requiresCertificateDecision: true)
        let connection = MockCoordinatorConnection()
        let certificateEvent = expectSessionEvent(in: harness) { self.certificateRequest(from: $0) != nil }

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(handshakeFrame(identity("remote")), from: connection)
        await fulfillment(of: [certificateEvent], timeout: 1)
        try await Task.sleep(nanoseconds: 200_000_000)

        try XCTUnwrap(harness.sessionEvents.compactMap { certificateRequest(from: $0) }.first).handler(true)
        harness.coordinator.receiveFrame(PeerNetworkFrame(kind: .admitted, payload: Data()), from: connection)

        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
        XCTAssertEqual(connection.cancelCallCount, 2, "Timeout cancels once; the stray admission cancels again")
    }

    internal func testAdmittedFrameOutsideCertificateModeCancelsConnection() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(PeerNetworkFrame(kind: .admitted, payload: Data()), from: connection)

        XCTAssertGreaterThanOrEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
    }

    // MARK: Invitations

    internal func testOutboundConnectionSendsInvitationWithContextAndTimeout() throws {
        let harness = Harness(localPeer: Peer(identity: identity("local"), status: .currentUser))
        let connection = MockCoordinatorConnection()
        let context = Data("join".utf8)

        harness.coordinator.addPendingConnection(connection, direction: .outbound,
            invitation: PeerNetworkInvitation(context: context, timeout: 25))

        let frame = try XCTUnwrap(connection.sentFrames.last)
        XCTAssertEqual(frame.kind, .invitation)
        XCTAssertEqual(try JSONDecoder().decode(PeerNetworkInvitation.self, from: frame.payload),
            PeerNetworkInvitation(context: context, timeout: 25))
    }

    internal func testInboundInvitationIsHeldUntilAcceptedAndRemotelyAdmitted() async throws {
        let harness = await makeHarness()
        harness.acceptsInvitations = false
        let connection = MockCoordinatorConnection()
        let remoteIdentity = identity("remote")
        let context = Data("table-7".utf8)
        let invitationEvent = expectSessionEvent(in: harness) { self.invitationRequest(from: $0) != nil }
        let connectedEvent = expectSessionEvent(in: harness) { self.devicesChangedPeer(from: $0)?.status == .connected }

        harness.coordinator.addPendingConnection(connection, direction: .inbound)
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
        await harness.sessionObserver.flush()
        XCTAssertTrue(harness.sessionEvents.compactMap { invitationRequest(from: $0) }.isEmpty,
            "Inbound peers must not be admitted or surfaced before they send an invitation")
        XCTAssertFalse(connection.sentFrames.contains { $0.kind == .admitted })

        harness.coordinator.receiveFrame(invitationFrame(PeerNetworkInvitation(context: context, timeout: 30)), from: connection)
        await fulfillment(of: [invitationEvent], timeout: 1)
        let request = try XCTUnwrap(harness.sessionEvents.compactMap { invitationRequest(from: $0) }.first)
        XCTAssertEqual(request.peer.identity, remoteIdentity)
        XCTAssertEqual(request.context, context)

        harness.coordinator.receiveFrame(admittedFrame(), from: connection)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty, "The remote's admission alone must not connect")

        request.handler(true)
        await fulfillment(of: [connectedEvent], timeout: 1)
        XCTAssertEqual(connection.sentFrames.filter { $0.kind == .admitted }.count, 1)
        XCTAssertEqual(harness.coordinator.connectedPeers.map { $0.identity }, [remoteIdentity])
    }

    internal func testDeclinedInvitationSendsDeclinedAndNeverConnects() async throws {
        let harness = await makeHarness()
        harness.acceptsInvitations = false
        let connection = MockCoordinatorConnection()
        let invitationEvent = expectSessionEvent(in: harness) { self.invitationRequest(from: $0) != nil }

        harness.coordinator.addPendingConnection(connection, direction: .inbound)
        harness.coordinator.receiveFrame(handshakeFrame(identity("remote")), from: connection)
        harness.coordinator.receiveFrame(invitationFrame(), from: connection)
        await fulfillment(of: [invitationEvent], timeout: 1)
        let request = try XCTUnwrap(harness.sessionEvents.compactMap { invitationRequest(from: $0) }.first)

        request.handler(false)
        request.handler(true)
        harness.coordinator.receiveFrame(admittedFrame(), from: connection)

        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
        XCTAssertEqual(connection.sentFrames.last?.kind, .declined)
        XCTAssertFalse(connection.sentFrames.contains { $0.kind == .admitted })
        XCTAssertGreaterThanOrEqual(connection.cancelCallCount, 1)
    }

    internal func testReceivingDeclinedCancelsOutboundInvitation() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(handshakeFrame(identity("remote")), from: connection)
        harness.coordinator.receiveFrame(PeerNetworkFrame(kind: .declined, payload: Data()), from: connection)
        harness.coordinator.receiveFrame(admittedFrame(), from: connection)

        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
        XCTAssertGreaterThanOrEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.sessionEvents.compactMap { devicesChangedPeer(from: $0) }.isEmpty)
    }

    internal func testInvitationProtocolViolationsCancelConnection() async {
        let harness = await makeHarness()
        let early = MockCoordinatorConnection()
        let outbound = MockCoordinatorConnection()
        let repeated = MockCoordinatorConnection()
        let oversized = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(early, direction: .inbound)
        harness.coordinator.receiveFrame(invitationFrame(), from: early)

        harness.coordinator.addPendingConnection(outbound, direction: .outbound)
        harness.coordinator.receiveFrame(handshakeFrame(identity("outbound")), from: outbound)
        harness.coordinator.receiveFrame(invitationFrame(), from: outbound)

        harness.acceptsInvitations = false
        harness.coordinator.addPendingConnection(repeated, direction: .inbound)
        harness.coordinator.receiveFrame(handshakeFrame(identity("repeated")), from: repeated)
        harness.coordinator.receiveFrame(invitationFrame(), from: repeated)
        harness.coordinator.receiveFrame(invitationFrame(), from: repeated)

        harness.coordinator.addPendingConnection(oversized, direction: .inbound)
        harness.coordinator.receiveFrame(handshakeFrame(identity("oversized")), from: oversized)
        harness.coordinator.receiveFrame(invitationFrame(PeerNetworkInvitation(
            context: Data(count: PeerNetworkInvitation.maxContextLength + 1))), from: oversized)

        for connection in [early, outbound, repeated, oversized] {
            XCTAssertGreaterThanOrEqual(connection.cancelCallCount, 1)
        }
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
    }

    internal func testInvitationTimeoutReplacesHandshakeDeadlineForInboundPeer() async throws {
        let harness = await makeHarness(policy: NetworkPeerConnectionPolicy(handshakeTimeout: 0.05))
        harness.acceptsInvitations = false
        let connection = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(connection, direction: .inbound)
        harness.coordinator.receiveFrame(handshakeFrame(identity("remote")), from: connection)
        harness.coordinator.receiveFrame(invitationFrame(PeerNetworkInvitation(timeout: 0.4)), from: connection)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(connection.cancelCallCount, 0, "A valid invitation extends the pending deadline")

        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(connection.cancelCallCount, 1, "An unanswered invitation expires at its timeout")
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
    }

    /// Completes an outbound admission: the remote handshake, then its `.admitted` frame.
    private func connect(_ remoteIdentity: PeerIdentity, on connection: MockCoordinatorConnection, in harness: Harness) {
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
        harness.coordinator.receiveFrame(admittedFrame(), from: connection)
    }

    /// Completes an inbound admission; the harness accepts the invitation asynchronously.
    private func connectInbound(_ remoteIdentity: PeerIdentity,
        on connection: MockCoordinatorConnection,
        in harness: Harness) async {
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
        harness.coordinator.receiveFrame(invitationFrame(), from: connection)
        await harness.sessionObserver.flush()
        _ = harness.coordinator.connectedPeers
        harness.coordinator.receiveFrame(admittedFrame(), from: connection)
    }

    /// Delivers frames between two coordinators until neither side sends anything new.
    private func exchangeFrames(_ first: Harness, _ firstConnection: MockCoordinatorConnection,
        _ second: Harness, _ secondConnection: MockCoordinatorConnection) async {
        var deliveredToFirst = 0
        var deliveredToSecond = 0
        while deliveredToFirst < secondConnection.sentFrames.count || deliveredToSecond < firstConnection.sentFrames.count {
            while deliveredToFirst < secondConnection.sentFrames.count {
                first.coordinator.receiveFrame(secondConnection.sentFrames[deliveredToFirst], from: firstConnection)
                deliveredToFirst += 1
            }
            while deliveredToSecond < firstConnection.sentFrames.count {
                second.coordinator.receiveFrame(firstConnection.sentFrames[deliveredToSecond], from: secondConnection)
                deliveredToSecond += 1
            }
            await first.sessionObserver.flush()
            await second.sessionObserver.flush()
            _ = first.coordinator.connectedPeers
            _ = second.coordinator.connectedPeers
        }
    }

    private func admittedFrame() -> PeerNetworkFrame {
        return PeerNetworkFrame(kind: .admitted, payload: Data())
    }

    private func invitationFrame(_ invitation: PeerNetworkInvitation = PeerNetworkInvitation()) -> PeerNetworkFrame {
        return PeerNetworkFrame(kind: .invitation, payload: try! JSONEncoder().encode(invitation))
    }

    private func invitationRequest(from event: PeerSessionEvent?) -> (peer: Peer, context: Data?, handler: (Bool) -> Void)? {
        guard case .didReceiveInvitation(peer: let peer, context: let context, handler: let handler)? = event else {
            return nil
        }
        return (peer, context, handler)
    }

    private func certificateRequest(from event: PeerSessionEvent?) -> (peer: Peer, certificate: [Any]?, handler: (Bool) -> Void)? {
        guard case .didReceiveCertificate(peer: let peer, certificate: let certificate, handler: let handler)? = event else {
            return nil
        }
        return (peer, certificate, handler)
    }

    private func expectSessionEvent(in harness: Harness, matching predicate: @escaping (PeerSessionEvent) -> Bool) -> XCTestExpectation {
        let expectation = expectation(description: "Session event received")
        harness.sessionEventPredicates.append((predicate, expectation))
        return expectation
    }

    private func makeHarness(localIdentifier: String = "local",
        policy: NetworkPeerConnectionPolicy = NetworkPeerConnectionPolicy(),
        requiresCertificateDecision: Bool = false,
        handshakeEncoder: @escaping NetworkPeerCoordinator<MockCoordinatorConnection>.HandshakeEncoder = {
            try JSONEncoder().encode($0)
        }) async -> Harness {
        let harness = Harness(localPeer: Peer(identity: identity(localIdentifier), status: .currentUser),
            policy: policy,
            requiresCertificateDecision: requiresCertificateDecision,
            handshakeEncoder: handshakeEncoder)
        await harness.observeEvents()
        return harness
    }

    private func handshakeFrame(_ identity: PeerIdentity,
        protocolVersion: Int = PeerNetworkHandshake.currentProtocolVersion) -> PeerNetworkFrame {
        let handshake = PeerNetworkHandshake(identity: identity, protocolVersion: protocolVersion)
        let payload = try! JSONEncoder().encode(handshake)
        return PeerNetworkFrame(kind: .handshake, payload: payload)
    }

    private func devicesChangedPeer(from event: PeerSessionEvent?) -> Peer? {
        switch event {
        case .devicesChanged(peer: let peer, connectedPeers: _): return peer
        default: return nil
        }
    }

    private func receivedData(from event: PeerSessionEvent?) -> (peer: Peer, data: Data)? {
        switch event {
        case .didReceiveData(peer: let peer, data: let data): return (peer, data)
        default: return nil
        }
    }

    private func identity(_ identifier: String) -> PeerIdentity {
        return PeerIdentity(identifier: identifier, displayName: identifier)
    }
}

private final class Harness {
    internal let coordinator : NetworkPeerCoordinator<MockCoordinatorConnection>
    internal let localPeer : Peer
    internal private(set) var sessionEvents : [PeerSessionEvent] = []
    /// Accept inbound invitations like `.acceptAll`; tests of the decision itself turn this off.
    internal var acceptsInvitations = true
    internal var sessionEventPredicates : [((PeerSessionEvent) -> Bool, XCTestExpectation)] = []

    internal init(localPeer: Peer,
        policy: NetworkPeerConnectionPolicy = NetworkPeerConnectionPolicy(),
        requiresCertificateDecision: Bool = false,
        handshakeEncoder: @escaping NetworkPeerCoordinator<MockCoordinatorConnection>.HandshakeEncoder = {
            try JSONEncoder().encode($0)
        }) {
        let sessionObserver = Observable<PeerSessionEvent>(.none)
        self.localPeer = localPeer
        self.coordinator = NetworkPeerCoordinator<MockCoordinatorConnection>(
            localPeer: localPeer,
            sessionObserver: sessionObserver,
            policy: policy,
            requiresCertificateDecision: requiresCertificateDecision,
            handshakeEncoder: handshakeEncoder
        )

        self.sessionObserver = sessionObserver
    }

    fileprivate let sessionObserver : Observable<PeerSessionEvent>

    internal func observeEvents() async {
        await sessionObserver.addObserverAsync { [weak self] event in
            self?.sessionEvents.append(event)
            if self?.acceptsInvitations == true, case .didReceiveInvitation(peer: _, context: _, handler: let handler) = event {
                handler(true)
            }
            self?.fulfillSessionExpectations(matching: event)
        }
    }

    fileprivate func fulfillSessionExpectations(matching event: PeerSessionEvent) {
        for index in sessionEventPredicates.indices.reversed() {
            let (predicate, expectation) = sessionEventPredicates[index]
            guard predicate(event) else { continue }
            sessionEventPredicates.remove(at: index)
            expectation.fulfill()
        }
    }

}
