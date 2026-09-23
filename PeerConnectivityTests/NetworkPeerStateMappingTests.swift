//
//  NetworkPeerStateMappingTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import XCTest
import Network
@testable import PeerConnectivity

@available(iOS 13.0, macOS 10.15, *)
final class NetworkPeerStateMappingTests : XCTestCase {

    internal func testSetupMapsToNotConnected() {
        XCTAssertEqual(NetworkPeerStateMapping.status(for: .setup), .notConnected)
    }

    internal func testWaitingMapsToConnecting() {
        XCTAssertEqual(NetworkPeerStateMapping.status(for: .waiting(.posix(.ENETDOWN))), .connecting)
    }

    internal func testPreparingMapsToConnecting() {
        XCTAssertEqual(NetworkPeerStateMapping.status(for: .preparing), .connecting)
    }

    internal func testReadyMapsToConnected() {
        XCTAssertEqual(NetworkPeerStateMapping.status(for: .ready), .connected)
    }

    internal func testFailedMapsToNotConnected() {
        XCTAssertEqual(NetworkPeerStateMapping.status(for: .failed(.posix(.ECONNRESET))), .notConnected)
    }

    internal func testCancelledMapsToNotConnected() {
        XCTAssertEqual(NetworkPeerStateMapping.status(for: .cancelled), .notConnected)
    }

    internal func testReconnectOnlyForWaitingAndFailed() {
        XCTAssertTrue(NetworkPeerStateMapping.shouldAttemptReconnect(for: .waiting(.posix(.ENETDOWN))))
        XCTAssertTrue(NetworkPeerStateMapping.shouldAttemptReconnect(for: .failed(.posix(.ECONNRESET))))
        XCTAssertFalse(NetworkPeerStateMapping.shouldAttemptReconnect(for: .ready))
        XCTAssertFalse(NetworkPeerStateMapping.shouldAttemptReconnect(for: .cancelled))
    }
}
