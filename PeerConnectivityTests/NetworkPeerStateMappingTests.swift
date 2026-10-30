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

    internal func testLocalNetworkDenialIsRecognizedOnlyForDNSPolicyDenied() {
        let denied = NWError.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))

        XCTAssertTrue(NetworkPeerStateMapping.isLocalNetworkDenial(denied))
        XCTAssertFalse(NetworkPeerStateMapping.isLocalNetworkDenial(.dns(DNSServiceErrorType(kDNSServiceErr_NoSuchRecord))))
        XCTAssertFalse(NetworkPeerStateMapping.isLocalNetworkDenial(.posix(.ENETDOWN)))
    }

    internal func testBrowserFailureMapsToBrowsingFailed() {
        guard case .browsingFailed? = NetworkPeerStateMapping.error(for: NWBrowser.State.failed(.posix(.ENETDOWN))) else {
            return XCTFail("A failed browser must surface as browsingFailed")
        }
    }

    internal func testBrowserPolicyDenialMapsToLocalNetworkAccessDenied() {
        // NWBrowser.State.waiting is constructible only on iOS 14 / macOS 11 and later.
        guard #available(iOS 14.0, macOS 11.0, *) else { return }
        let state = NWBrowser.State.waiting(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied)))

        guard case .localNetworkAccessDenied? = NetworkPeerStateMapping.error(for: state) else {
            return XCTFail("A Local Network denial must surface as localNetworkAccessDenied")
        }
    }

    internal func testListenerFailureMapsToAdvertisingFailed() {
        guard case .advertisingFailed? = NetworkPeerStateMapping.error(for: NWListener.State.failed(.posix(.EADDRINUSE))) else {
            return XCTFail("A failed listener must surface as advertisingFailed")
        }
    }

    internal func testListenerPolicyDenialMapsToLocalNetworkAccessDenied() {
        let state = NWListener.State.waiting(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied)))

        guard case .localNetworkAccessDenied? = NetworkPeerStateMapping.error(for: state) else {
            return XCTFail("A Local Network denial must surface as localNetworkAccessDenied")
        }
    }

    internal func testRecoverableWaitingStatesAreNotReported() {
        XCTAssertNil(NetworkPeerStateMapping.error(for: NWListener.State.waiting(.posix(.ENETDOWN))))
        if #available(iOS 14.0, macOS 11.0, *) {
            XCTAssertNil(NetworkPeerStateMapping.error(for: NWBrowser.State.waiting(.posix(.ENETDOWN))))
        }
    }

    internal func testHealthyAndStoppedStatesAreNotReported() {
        XCTAssertNil(NetworkPeerStateMapping.error(for: NWBrowser.State.ready))
        XCTAssertNil(NetworkPeerStateMapping.error(for: NWBrowser.State.cancelled))
        XCTAssertNil(NetworkPeerStateMapping.error(for: NWListener.State.ready))
        XCTAssertNil(NetworkPeerStateMapping.error(for: NWListener.State.cancelled))
    }
}
