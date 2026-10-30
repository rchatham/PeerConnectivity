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
    internal var processedError : Error?

    internal func sendFrame(_ frame: PeerNetworkFrame, onProcessed: @escaping (Error?) -> Void) {
        sentFrames.append(frame)
        let error = processedError
        DispatchQueue.global().async { onProcessed(error) }
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

    internal func testCompletionReportsOnlyFailedAndUnconnectedPeers() {
        let registry = NetworkPeerConnectionRegistry<MockFrameConnection>(localIdentity: identity("local"))
        let healthyIdentity = identity("healthy")
        let failingIdentity = identity("failing")
        let missingIdentity = identity("missing")
        let healthy = MockFrameConnection()
        let failing = MockFrameConnection()
        failing.processedError = NSError(domain: "test", code: 32)
        let sender = NetworkPeerDataSender(registry: registry)
        let expectation = self.expectation(description: "Send completion")
        var reported : [PeerIdentity:Error] = [:]

        registry.register(healthy, for: healthyIdentity, direction: .outbound)
        registry.register(failing, for: failingIdentity, direction: .outbound)
        sender.sendData(Data([9]), toPeers: [healthyIdentity, failingIdentity, missingIdentity]) { failures in
            reported = failures
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(Set(reported.keys), [failingIdentity, missingIdentity])
        XCTAssertEqual((reported[failingIdentity] as NSError?)?.code, 32)
        guard case .peerNotConnected? = reported[missingIdentity] as? PeerConnectionError else {
            return XCTFail("Targets without a connection must fail with peerNotConnected")
        }
        XCTAssertEqual(healthy.sentFrames.count, 1)
    }

    internal func testBroadcastCompletionWithNoConnectedPeersReportsNoFailures() {
        let registry = NetworkPeerConnectionRegistry<MockFrameConnection>(localIdentity: identity("local"))
        let sender = NetworkPeerDataSender(registry: registry)
        let expectation = self.expectation(description: "Send completion")

        sender.sendData(Data([1]), toPeers: []) { failures in
            XCTAssertTrue(failures.isEmpty)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
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
