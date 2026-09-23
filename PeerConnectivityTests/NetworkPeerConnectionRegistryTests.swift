//
//  NetworkPeerConnectionRegistryTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import XCTest
@testable import PeerConnectivity

private final class MockNetworkConnection : NetworkPeerConnectionCancellable {
    internal private(set) var cancelCallCount = 0

    internal func cancel() {
        cancelCallCount += 1
    }
}

final class NetworkPeerConnectionRegistryTests : XCTestCase {

    internal func testRegistersConnectionForPeerIdentity() {
        let registry = NetworkPeerConnectionRegistry<MockNetworkConnection>(localIdentity: localIdentity("a"))
        let connection = MockNetworkConnection()
        let remote = remoteIdentity("b")

        registry.register(connection, for: remote, direction: .outbound)

        XCTAssertTrue(registry.connection(for: remote) === connection)
        XCTAssertEqual(registry.connectedPeerIdentities, [remote])
    }

    internal func testDuplicateKeepsOutboundWhenLocalIdentifierSortsFirst() {
        let registry = NetworkPeerConnectionRegistry<MockNetworkConnection>(localIdentity: localIdentity("a"))
        let remote = remoteIdentity("b")
        let outbound = MockNetworkConnection()
        let inbound = MockNetworkConnection()

        registry.register(outbound, for: remote, direction: .outbound)
        registry.register(inbound, for: remote, direction: .inbound)

        XCTAssertTrue(registry.connection(for: remote) === outbound)
        XCTAssertEqual(outbound.cancelCallCount, 0)
        XCTAssertEqual(inbound.cancelCallCount, 1)
    }

    internal func testDuplicateKeepsInboundWhenLocalIdentifierSortsLast() {
        let registry = NetworkPeerConnectionRegistry<MockNetworkConnection>(localIdentity: localIdentity("z"))
        let remote = remoteIdentity("b")
        let outbound = MockNetworkConnection()
        let inbound = MockNetworkConnection()

        registry.register(outbound, for: remote, direction: .outbound)
        registry.register(inbound, for: remote, direction: .inbound)

        XCTAssertTrue(registry.connection(for: remote) === inbound)
        XCTAssertEqual(outbound.cancelCallCount, 1)
        XCTAssertEqual(inbound.cancelCallCount, 0)
    }

    internal func testCancelAllCancelsAndClearsConnections() {
        let registry = NetworkPeerConnectionRegistry<MockNetworkConnection>(localIdentity: localIdentity("a"))
        let first = MockNetworkConnection()
        let second = MockNetworkConnection()
        let firstRemote = remoteIdentity("b")
        let secondRemote = remoteIdentity("c")

        registry.register(first, for: firstRemote, direction: .outbound)
        registry.register(second, for: secondRemote, direction: .outbound)
        registry.cancelAll()

        XCTAssertEqual(first.cancelCallCount, 1)
        XCTAssertEqual(second.cancelCallCount, 1)
        XCTAssertTrue(registry.connectedPeerIdentities.isEmpty)
    }

    private func localIdentity(_ identifier: String) -> PeerIdentity {
        return PeerIdentity(identifier: identifier, displayName: "Local")
    }

    private func remoteIdentity(_ identifier: String) -> PeerIdentity {
        return PeerIdentity(identifier: identifier, displayName: "Remote")
    }
}
