//
//  NetworkPeerCoordinatorTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import XCTest
@testable import PeerConnectivity

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

    internal func testHandshakeRegistersConnectedPeerAndEmitsSessionEvent() async throws {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()
        let remoteIdentity = identity("remote")

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
        await Task.yield()

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

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
        harness.coordinator.receiveFrame(PeerNetworkFrame(kind: .data, payload: payload), from: connection)
        try await Task.sleep(nanoseconds: 50_000_000)

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

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: connection)
        harness.coordinator.removeConnection(connection)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
        let peer = try XCTUnwrap(harness.sessionEvents.compactMap { devicesChangedPeer(from: $0) }
            .first { $0.status == .notConnected })
        XCTAssertEqual(peer, Peer(identity: remoteIdentity, status: .notConnected))
        XCTAssertEqual(peer.status, .notConnected)
    }

    internal func testRemovingDuplicateLoserDoesNotRemoveWinningConnection() async throws {
        let harness = await makeHarness(localIdentifier: "zlocal")
        let outbound = MockCoordinatorConnection()
        let inbound = MockCoordinatorConnection()
        let remoteIdentity = identity("remote")

        harness.coordinator.addPendingConnection(outbound, direction: .outbound)
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: outbound)
        try await Task.sleep(nanoseconds: 50_000_000)
        let sessionEventCount = harness.sessionEvents.count
        harness.coordinator.addPendingConnection(inbound, direction: .inbound)
        harness.coordinator.receiveFrame(handshakeFrame(remoteIdentity), from: inbound)
        harness.coordinator.removeConnection(outbound)

        XCTAssertEqual(outbound.cancelCallCount, 1)
        XCTAssertEqual(harness.sessionEvents.count, sessionEventCount)
        XCTAssertEqual(harness.coordinator.connectedPeers, [Peer(identity: remoteIdentity, status: .connected)])

        harness.coordinator.removeConnection(inbound)
        try await Task.sleep(nanoseconds: 50_000_000)

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

    internal func testInvalidHandshakeCancelsPendingConnection() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(PeerNetworkFrame(kind: .handshake, payload: Data([1, 2, 3])), from: connection)

        XCTAssertEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
    }

    internal func testSelfHandshakeCancelsPendingConnection() async {
        let harness = await makeHarness()
        let connection = MockCoordinatorConnection()

        harness.coordinator.addPendingConnection(connection, direction: .outbound)
        harness.coordinator.receiveFrame(handshakeFrame(harness.localPeer.identity), from: connection)

        XCTAssertEqual(connection.cancelCallCount, 1)
        XCTAssertTrue(harness.coordinator.connectedPeers.isEmpty)
    }

    internal func testSelfDiscoveryIsIgnored() async {
        let harness = await makeHarness()
        let browserEventCount = harness.browserEvents.count

        harness.coordinator.foundPeer(identity: harness.localPeer.identity)
        harness.coordinator.lostPeer(identity: harness.localPeer.identity)
        await Task.yield()

        XCTAssertEqual(harness.browserEvents.count, browserEventCount)
    }

    internal func testFoundAndLostPeerEmitBrowserEvents() async throws {
        let harness = await makeHarness()
        let remoteIdentity = identity("remote")

        harness.coordinator.foundPeer(identity: remoteIdentity)
        try await Task.sleep(nanoseconds: 10_000_000)
        let foundPeer = try XCTUnwrap(foundPeer(from: harness.browserEvents.last))
        XCTAssertEqual(foundPeer, Peer(identity: remoteIdentity, status: .notConnected))

        harness.coordinator.lostPeer(identity: remoteIdentity)
        try await Task.sleep(nanoseconds: 10_000_000)
        let lostPeer = try XCTUnwrap(lostPeer(from: harness.browserEvents.last))
        XCTAssertEqual(lostPeer, Peer(identity: remoteIdentity, status: .notConnected))
    }

    private func makeHarness(localIdentifier: String = "local") async -> Harness {
        let harness = Harness(localPeer: Peer(identity: identity(localIdentifier), status: .currentUser))
        await harness.observeEvents()
        return harness
    }

    private func handshakeFrame(_ identity: PeerIdentity) -> PeerNetworkFrame {
        let handshake = PeerNetworkHandshake(identity: identity)
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

    private func foundPeer(from event: PeerBrowserEvent?) -> Peer? {
        switch event {
        case .foundPeer(let peer, _): return peer
        default: return nil
        }
    }

    private func lostPeer(from event: PeerBrowserEvent?) -> Peer? {
        switch event {
        case .lostPeer(let peer): return peer
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
    internal private(set) var browserEvents : [PeerBrowserEvent] = []
    internal private(set) var advertiserEvents : [PeerAdvertiserEvent] = []

    internal init(localPeer: Peer) {
        let sessionObserver = Observable<PeerSessionEvent>(.none)
        let browserObserver = Observable<PeerBrowserEvent>(.none)
        let advertiserObserver = Observable<PeerAdvertiserEvent>(.none)
        self.localPeer = localPeer
        self.coordinator = NetworkPeerCoordinator<MockCoordinatorConnection>(
            localPeer: localPeer,
            sessionObserver: sessionObserver,
            browserObserver: browserObserver,
            advertiserObserver: advertiserObserver
        )

        self.sessionObserver = sessionObserver
        self.browserObserver = browserObserver
        self.advertiserObserver = advertiserObserver
    }

    fileprivate let sessionObserver : Observable<PeerSessionEvent>
    fileprivate let browserObserver : Observable<PeerBrowserEvent>
    fileprivate let advertiserObserver : Observable<PeerAdvertiserEvent>

    internal func observeEvents() async {
        sessionObserver.addObserver { [weak self] in self?.sessionEvents.append($0) }
        browserObserver.addObserver { [weak self] in self?.browserEvents.append($0) }
        advertiserObserver.addObserver { [weak self] in self?.advertiserEvents.append($0) }
    }
}
