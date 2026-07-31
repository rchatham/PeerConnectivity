//
//  PeerConnectionBackendTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 7/30/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
@testable import PeerConnectivity

private final class BackendSelectorMockSessionTransport : PeerSessionTransport {
    internal let peer : Peer
    internal var connectedPeers : [Peer] = []

    internal init(peer: Peer) {
        self.peer = peer
    }

    internal func startSession() {}

    internal func stopSession() {}

    internal func sendData(_ data: Data, toPeers peers: [Peer]) {}

    internal func sendDataStream(_ streamName: String, toPeer peer: Peer) throws -> OutputStream {
        return OutputStream.toMemory()
    }

    internal func sendResourceAtURL(_ resourceURL: URL,
        withName name: String,
        toPeer peer: Peer,
        withCompletionHandler completion: ((Error?)->Void)?) -> Progress? {
        return nil
    }
}

private struct BackendSelectorFactoryHarness {
    internal var factory : PeerConnectionTransportFactory {
        return PeerConnectionTransportFactory(
            makeSession: { peer, _ in
                return BackendSelectorMockSessionTransport(peer: peer)
            },
            makeBrowser: { _, _, _ in
                return BackendSelectorNoOpBrowserTransport()
            },
            makeAdvertiser: { _, _, _ in
                return BackendSelectorNoOpAdvertiserTransport()
            },
            makeAdvertiserAssisstant: { _, _, _ in
                return BackendSelectorNoOpAdvertiserAssisstantTransport()
            }
        )
    }
}

private struct BackendSelectorNoOpBrowserTransport : PeerBrowserTransport {
    internal func invitePeer(_ peer: Peer, withContext context: Data?, timeout: TimeInterval) {}

    internal func startBrowsing() {}

    internal func stopBrowsing() {}
}

private struct BackendSelectorNoOpAdvertiserTransport : PeerAdvertiserTransport {
    internal func startAdvertising() {}

    internal func stopAdvertising() {}
}

private struct BackendSelectorNoOpAdvertiserAssisstantTransport : PeerAdvertiserAssisstantTransport {
    internal func startAdvertisingAssisstant() {}

    internal func stopAdvertisingAssisstant() {}
}

final class PeerConnectionBackendTests : XCTestCase {

    internal func testDefaultInitializerUsesMultipeerConnectivityBackend() {
        let manager = PeerConnectionManager(serviceType: "backend-default", displayName: "Local")

        XCTAssertEqual(manager.backend, .multipeerConnectivity)
        XCTAssertTrue(manager.isUsingMultipeerConnectivityTransport)
        XCTAssertFalse(manager.isUsingNetworkFrameworkTransport)
    }

    internal func testExplicitMultipeerBackendUsesMultipeerFactory() {
        let manager = PeerConnectionManager(serviceType: "backend-mc",
            displayName: "Local",
            backend: .multipeerConnectivity)

        XCTAssertEqual(manager.backend, .multipeerConnectivity)
        XCTAssertTrue(manager.isUsingMultipeerConnectivityTransport)
        XCTAssertFalse(manager.isUsingNetworkFrameworkTransport)
        XCTAssertNotNil(manager.multipeerSession)
    }

    internal func testNetworkBackendUsesNetworkTransportFactoryWhenAvailable() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let manager = PeerConnectionManager(serviceType: "backend-network",
            displayName: "Local",
            backend: .networkFramework)

        XCTAssertEqual(manager.backend, .networkFramework)
        XCTAssertFalse(manager.isUsingMultipeerConnectivityTransport)
        XCTAssertTrue(manager.isUsingNetworkFrameworkTransport)
    }

    internal func testNetworkBackendAutomaticStartUsesNetworkFactoryWhenAvailable() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let manager = PeerConnectionManager(serviceType: "backend-network-start",
            connectionType: .automatic,
            displayName: "Local",
            backend: .networkFramework)
        let expectation = self.expectation(description: "Network backend started")

        manager.listenOn({ event in
            switch event {
            case .started:
                expectation.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "started")

        manager.start()

        waitForExpectations(timeout: 1)
        XCTAssertEqual(manager.backend, .networkFramework)
        XCTAssertTrue(manager.isUsingNetworkFrameworkTransport)

        manager.stop()
    }

    internal func testNetworkBackendInviteOnlyStartsWithoutAdvertiserAssistantUIWhenAvailable() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let manager = PeerConnectionManager(serviceType: "backend-network-invite",
            connectionType: .inviteOnly,
            displayName: "Local",
            backend: .networkFramework)
        let expectation = self.expectation(description: "Network invite-only backend started")

        manager.listenOn({ event in
            switch event {
            case .started:
                expectation.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "started")

        manager.start()

        waitForExpectations(timeout: 1)
        XCTAssertTrue(manager.isUsingNetworkFrameworkTransport)

        manager.stop()
    }

    internal func testTransportFactoryInitializerRemainsMultipeerConnectivityBackend() {
        let harness = BackendSelectorFactoryHarness()
        let manager = PeerConnectionManager(serviceType: "backend-custom-factory",
            displayName: "Local",
            transportFactory: harness.factory)

        XCTAssertEqual(manager.backend, .multipeerConnectivity)
        XCTAssertFalse(manager.isUsingMultipeerConnectivityTransport)
        XCTAssertFalse(manager.isUsingNetworkFrameworkTransport)
    }
}
