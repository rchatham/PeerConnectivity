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
        await fulfillment(of: [expectation], timeout: 1)

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

        XCTAssertEqual(harness.browserEvents.count, browserEventCount)
    }

    internal func testFoundAndLostPeerEmitBrowserEvents() async throws {
        let harness = await makeHarness()
        let remoteIdentity = identity("remote")

        let foundExpectation = expectBrowserEvent(in: harness) { event in
            return self.foundPeer(from: event) == Peer(identity: remoteIdentity, status: .notConnected)
        }

        harness.coordinator.foundPeer(identity: remoteIdentity)
        await fulfillment(of: [foundExpectation], timeout: 1)
        let found = try XCTUnwrap(foundPeer(from: harness.browserEvents.last))
        XCTAssertEqual(found, Peer(identity: remoteIdentity, status: .notConnected))

        let lostExpectation = expectBrowserEvent(in: harness) { event in
            return self.lostPeer(from: event) == Peer(identity: remoteIdentity, status: .notConnected)
        }

        harness.coordinator.lostPeer(identity: remoteIdentity)
        await fulfillment(of: [lostExpectation], timeout: 1)
        let lost = try XCTUnwrap(lostPeer(from: harness.browserEvents.last))
        XCTAssertEqual(lost, Peer(identity: remoteIdentity, status: .notConnected))
    }

    private func expectSessionEvent(in harness: Harness, matching predicate: @escaping (PeerSessionEvent) -> Bool) -> XCTestExpectation {
        let expectation = expectation(description: "Session event received")
        harness.sessionEventPredicates.append((predicate, expectation))
        return expectation
    }

    private func expectBrowserEvent(in harness: Harness, matching predicate: @escaping (PeerBrowserEvent) -> Bool) -> XCTestExpectation {
        let expectation = expectation(description: "Browser event received")
        harness.browserEventPredicates.append((predicate, expectation))
        return expectation
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
    internal var sessionEventPredicates : [((PeerSessionEvent) -> Bool, XCTestExpectation)] = []
    internal var browserEventPredicates : [((PeerBrowserEvent) -> Bool, XCTestExpectation)] = []

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
        await sessionObserver.addObserverAsync { [weak self] event in
            self?.sessionEvents.append(event)
            self?.fulfillSessionExpectations(matching: event)
        }
        await browserObserver.addObserverAsync { [weak self] event in
            self?.browserEvents.append(event)
            self?.fulfillBrowserExpectations(matching: event)
        }
        await advertiserObserver.addObserverAsync { [weak self] in self?.advertiserEvents.append($0) }
    }

    fileprivate func fulfillSessionExpectations(matching event: PeerSessionEvent) {
        for index in sessionEventPredicates.indices.reversed() {
            let (predicate, expectation) = sessionEventPredicates[index]
            guard predicate(event) else { continue }
            sessionEventPredicates.remove(at: index)
            expectation.fulfill()
        }
    }

    fileprivate func fulfillBrowserExpectations(matching event: PeerBrowserEvent) {
        for index in browserEventPredicates.indices.reversed() {
            let (predicate, expectation) = browserEventPredicates[index]
            guard predicate(event) else { continue }
            browserEventPredicates.remove(at: index)
            expectation.fulfill()
        }
    }
}
