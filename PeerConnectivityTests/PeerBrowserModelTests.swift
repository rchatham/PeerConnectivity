//
//  PeerBrowserModelTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import XCTest
@testable import PeerConnectivity

private final class BrowserModelMockSessionTransport : PeerSessionTransport {
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

private final class BrowserModelMockBrowserTransport : PeerBrowserTransport {
    internal private(set) var invitedPeers : [Peer] = []

    internal func invitePeer(_ peer: Peer, withContext context: Data?, timeout: TimeInterval) {
        invitedPeers.append(peer)
    }

    internal func startBrowsing() {}

    internal func stopBrowsing() {}
}

private struct BrowserModelNoOpAdvertiserTransport : PeerAdvertiserTransport {
    internal func startAdvertising() {}

    internal func stopAdvertising() {}
}

private struct BrowserModelNoOpAdvertiserAssisstantTransport : PeerAdvertiserAssisstantTransport {
    internal func startAdvertisingAssisstant() {}

    internal func stopAdvertisingAssisstant() {}
}

private final class PeerBrowserModelHarness {
    internal let browser = BrowserModelMockBrowserTransport()
    internal var browserObserver : Observable<PeerBrowserEvent>?
    internal var sessionObserver : Observable<PeerSessionEvent>?

    internal var factory : PeerConnectionTransportFactory {
        return PeerConnectionTransportFactory(
            makeSession: { [weak self] peer, _, observer in
                self?.sessionObserver = observer
                return BrowserModelMockSessionTransport(peer: peer)
            },
            makeBrowser: { [weak self] _, _, observer in
                self?.browserObserver = observer
                return self!.browser
            },
            makeAdvertiser: { _, _, _, _ in
                return BrowserModelNoOpAdvertiserTransport()
            },
            makeAdvertiserAssisstant: { _, _, _, _ in
                return BrowserModelNoOpAdvertiserAssisstantTransport()
            }
        )
    }
}

final class PeerBrowserModelTests : XCTestCase {

    internal func testModelTracksFoundAndLostPeers() {
        let harness = PeerBrowserModelHarness()
        let manager = makeManager(harness: harness)
        let peer = Peer(identity: PeerIdentity(identifier: "remote", displayName: "Remote"), status: .notConnected)
        let foundExpectation = expectation(description: "Model found peer")
        let lostExpectation = expectation(description: "Model lost peer")
        foundExpectation.assertForOverFulfill = false
        lostExpectation.assertForOverFulfill = false
        let model = PeerBrowserModel(manager: manager) { peers in
            if peers == [peer] {
                foundExpectation.fulfill()
            } else if peers.isEmpty {
                lostExpectation.fulfill()
            }
        }

        model.startObserving()
        manager.startBrowsingOnly()
        harness.browserObserver?.value = .foundPeer(peer, discoveryInfo: nil)
        wait(for: [foundExpectation], timeout: 1)
        XCTAssertEqual(model.discoveredPeers, [peer])

        harness.browserObserver?.value = .lostPeer(peer)
        wait(for: [lostExpectation], timeout: 1)
        XCTAssertTrue(model.discoveredPeers.isEmpty)
    }

    internal func testModelUpdatesDiscoveredPeerStatusFromDevicesChanged() {
        let harness = PeerBrowserModelHarness()
        let manager = makeManager(harness: harness)
        let identity = PeerIdentity(identifier: "remote", displayName: "Remote")
        let foundPeer = Peer(identity: identity, status: .notConnected)
        let connectedPeer = Peer(identity: identity, status: .connected)
        let otherPeer = Peer(identity: PeerIdentity(identifier: "other", displayName: "Other"), status: .notConnected)
        let expectation = self.expectation(description: "Model updated peer status")
        expectation.assertForOverFulfill = false
        let model = PeerBrowserModel(manager: manager) { peers in
            if peers.first?.status == .connected {
                expectation.fulfill()
            }
        }

        model.startObserving()
        manager.startBrowsingOnly()
        harness.browserObserver?.value = .foundPeer(foundPeer, discoveryInfo: nil)
        harness.sessionObserver?.value = .devicesChanged(peer: connectedPeer)

        waitForExpectations(timeout: 1)
        XCTAssertEqual(model.discoveredPeers.first?.status, .connected)

        harness.browserObserver?.value = .foundPeer(otherPeer, discoveryInfo: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(model.discoveredPeers.first?.status, .connected)
    }

    internal func testInvitePeerForwardsToManager() {
        let harness = PeerBrowserModelHarness()
        let manager = makeManager(harness: harness)
        let model = PeerBrowserModel(manager: manager)
        let peer = Peer(identity: PeerIdentity(identifier: "remote", displayName: "Remote"), status: .notConnected)

        model.invitePeer(peer)

        XCTAssertEqual(harness.browser.invitedPeers, [peer])
    }

    internal func testStopObservingRemovesModelListener() {
        let harness = PeerBrowserModelHarness()
        let manager = makeManager(harness: harness)
        let model = PeerBrowserModel(manager: manager)
        let peer = Peer(identity: PeerIdentity(identifier: "remote", displayName: "Remote"), status: .notConnected)

        model.startObserving()
        manager.startBrowsingOnly()
        model.stopObserving()
        harness.browserObserver?.value = .foundPeer(peer, discoveryInfo: nil)

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(model.discoveredPeers.isEmpty)
    }

    private func makeManager(harness: PeerBrowserModelHarness) -> PeerConnectionManager {
        return PeerConnectionManager(serviceType: "browser-model",
            connectionType: .custom,
            displayName: "Local",
            transportFactory: harness.factory)
    }
}
