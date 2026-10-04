//
//  NetworkPeerDataSenderTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import XCTest
@testable import PeerConnectivity

private final class MockFrameConnection : NetworkPeerFrameSending {
    internal private(set) var sentFrames : [PeerNetworkFrame] = []
    internal private(set) var cancelCallCount = 0

    internal func sendFrame(_ frame: PeerNetworkFrame) {
        sentFrames.append(frame)
    }

    internal func cancel() {
        cancelCallCount += 1
    }
}

final class NetworkPeerDataSenderTests : XCTestCase {

    internal func testBroadcastSendsDataFrameToAllRegisteredPeers() {
        let registry = NetworkPeerConnectionRegistry<MockFrameConnection>(localIdentity: identity("local"))
        let firstIdentity = identity("first")
        let secondIdentity = identity("second")
        let first = MockFrameConnection()
        let second = MockFrameConnection()
        let sender = NetworkPeerDataSender(registry: registry)
        let payload = Data([1, 2, 3])

        registry.register(first, for: firstIdentity, direction: .outbound)
        registry.register(second, for: secondIdentity, direction: .outbound)
        sender.sendData(payload)

        XCTAssertEqual(first.sentFrames, [PeerNetworkFrame(kind: .data, payload: payload)])
        XCTAssertEqual(second.sentFrames, [PeerNetworkFrame(kind: .data, payload: payload)])
    }

    internal func testTargetedSendOnlySendsToRequestedPeers() {
        let registry = NetworkPeerConnectionRegistry<MockFrameConnection>(localIdentity: identity("local"))
        let firstIdentity = identity("first")
        let secondIdentity = identity("second")
        let first = MockFrameConnection()
        let second = MockFrameConnection()
        let sender = NetworkPeerDataSender(registry: registry)
        let payload = Data([4, 5, 6])

        registry.register(first, for: firstIdentity, direction: .outbound)
        registry.register(second, for: secondIdentity, direction: .outbound)
        sender.sendData(payload, toPeers: [secondIdentity])

        XCTAssertTrue(first.sentFrames.isEmpty)
        XCTAssertEqual(second.sentFrames, [PeerNetworkFrame(kind: .data, payload: payload)])
    }

    internal func testMissingTargetPeerIsIgnored() {
        let registry = NetworkPeerConnectionRegistry<MockFrameConnection>(localIdentity: identity("local"))
        let sender = NetworkPeerDataSender(registry: registry)

        sender.sendData(Data([7, 8, 9]), toPeers: [identity("missing")])

        XCTAssertTrue(registry.connectedPeerIdentities.isEmpty)
    }

    private func identity(_ identifier: String) -> PeerIdentity {
        return PeerIdentity(identifier: identifier, displayName: identifier)
    }
}
