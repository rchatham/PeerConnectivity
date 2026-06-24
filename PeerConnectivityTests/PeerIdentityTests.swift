//
//  PeerIdentityTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import XCTest
@testable import PeerConnectivity

final class PeerIdentityTests : XCTestCase {

    internal func testPeerDisplayNameUsesFrameworkNeutralIdentity() {
        let identity = PeerIdentity(identifier: "peer-1", displayName: "Remote Peer")
        let peer = Peer(identity: identity, status: .notConnected)

        XCTAssertEqual(peer.displayName, "Remote Peer")
    }

    internal func testPeerEqualityUsesIdentity() {
        let identity = PeerIdentity(identifier: "peer-1", displayName: "Remote Peer")
        let first = Peer(identity: identity, status: .connecting)
        let second = Peer(identity: identity, status: .connected)

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 1)
    }

    internal func testPeersWithSameDisplayNameAndDifferentIdentifiersAreDistinct() {
        let first = Peer(identity: PeerIdentity(identifier: "peer-1", displayName: "Remote Peer"), status: .connected)
        let second = Peer(identity: PeerIdentity(identifier: "peer-2", displayName: "Remote Peer"), status: .connected)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 2)
    }
}
