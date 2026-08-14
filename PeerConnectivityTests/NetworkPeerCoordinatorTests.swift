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
    internal private(set) var cancelCallCount = 0

    internal func sendFrame(_ frame: PeerNetworkFrame) {
        sentFrames.append(frame)
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

        XCTAssertEqual(connection.sentFrames.count, 1)
        XCTAssertEqual(connection.sentFrames.first?.kind, .handshake)
        let payload = try XCTUnwrap(connection.sentFrames.first?.payload)
        let handshake = try JSONDecoder().decode(PeerNetworkHandshake.self, from: payload)
        XCTAssertEqual(handshake.identity, harness.localPeer.identity)
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
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(harness.coordinator.connectedPeers, [Peer(identity: remoteIdentity, status: .connected)])
        let peer = try XCTUnwrap(devicesChangedPeer(from: harness.sessionEvents.last))
        XCTAssertEqual(peer, Peer(identity: remoteIdentity, status: .connected))
        XCTAssertEqual(peer.status, .connected)
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
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
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
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
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
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
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
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: outbound)
        await fulfillment(of: [connectedExpectation], timeout: 1)
        let sessionEventCount = harness.sessionEvents.count
        harness.coordinator.addPendingConnection(inbound, direction: .inbound)
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: inbound)
        harness.coordinator.removeConnection(outbound)

        XCTAssertEqual(outbound.cancelCallCount, 1)
        XCTAssertEqual(harness.sessionEvents.count, sessionEventCount)
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
        harness.coordinator.receiveFrame(handshakeFrame(identity("remote")), from: registered)
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
        harness.coordinator.receiveFrame(handshakeFrame(identity("first")), from: first)
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
        harness.coordinator.receiveFrame(handshakeFrame(identity("first")), from: first)
        harness.coordinator.receiveFrame(handshakeFrame(identity("second")), from: second)

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
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(connection.cancelCallCount, 0)
        XCTAssertEqual(harness.coordinator.connectedPeers.map { $0.identity }, [remoteIdentity])
        XCTAssertEqual(harness.sessionEvents.compactMap { devicesChangedPeer(from: $0) }.count, 1)
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
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: registered)
        registered.clearSentFrames()
        harness.coordinator.addPendingConnection(duplicate, direction: .inbound)
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: duplicate)
        duplicate.clearSentFrames()
        harness.coordinator.sendData(payload)

        XCTAssertEqual(duplicate.cancelCallCount, 1)
        XCTAssertEqual(duplicate.sentFrames, [])
        XCTAssertEqual(registered.sentFrames, [PeerNetworkFrame(kind: .data, payload: payload)])
        XCTAssertEqual(harness.coordinator.connectedPeers, [Peer(identity: remoteIdentity, status: .connected)])
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

    private func expectSessionEvent(in harness: Harness, matching predicate: @escaping (PeerSessionEvent) -> Bool) -> XCTestExpectation {
        let expectation = expectation(description: "Session event received")
        harness.sessionEventPredicates.append((predicate, expectation))
        return expectation
    }

    private func makeHarness(localIdentifier: String = "local",
        policy: NetworkPeerConnectionPolicy = NetworkPeerConnectionPolicy(),
        handshakeEncoder: @escaping NetworkPeerCoordinator<MockCoordinatorConnection>.HandshakeEncoder = {
            try JSONEncoder().encode($0)
        }) async -> Harness {
        let harness = Harness(localPeer: Peer(identity: identity(localIdentifier), status: .currentUser),
            policy: policy,
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
        case .devicesChanged(peer: let peer): return peer
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
    internal var sessionEventPredicates : [((PeerSessionEvent) -> Bool, XCTestExpectation)] = []

    internal init(localPeer: Peer,
        policy: NetworkPeerConnectionPolicy = NetworkPeerConnectionPolicy(),
        handshakeEncoder: @escaping NetworkPeerCoordinator<MockCoordinatorConnection>.HandshakeEncoder = {
            try JSONEncoder().encode($0)
        }) {
        let sessionObserver = Observable<PeerSessionEvent>(.none)
        self.localPeer = localPeer
        self.coordinator = NetworkPeerCoordinator<MockCoordinatorConnection>(
            localPeer: localPeer,
            sessionObserver: sessionObserver,
            policy: policy,
            handshakeEncoder: handshakeEncoder
        )

        self.sessionObserver = sessionObserver
    }

    fileprivate let sessionObserver : Observable<PeerSessionEvent>

    internal func observeEvents() async {
        await sessionObserver.addObserverAsync { [weak self] event in
            self?.sessionEvents.append(event)
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
