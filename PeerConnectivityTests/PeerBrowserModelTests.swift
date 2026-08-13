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

    internal func testModelTracksFoundAndLostPeers() async {
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
        await startBrowsingOnly(manager)
        await harness.browserObserver?.updateAsync(.foundPeer(peer, discoveryInfo: nil))
        await fulfillment(of: [foundExpectation], timeout: 1)
        XCTAssertEqual(model.discoveredPeers, [peer])

        await harness.browserObserver?.updateAsync(.lostPeer(peer))
        await fulfillment(of: [lostExpectation], timeout: 1)
        XCTAssertTrue(model.discoveredPeers.isEmpty)
    }

    internal func testModelUpdatesDiscoveredPeerStatusFromDevicesChanged() async {
        let harness = PeerBrowserModelHarness()
        let manager = makeManager(harness: harness)
        let identity = PeerIdentity(identifier: "remote", displayName: "Remote")
        let foundPeer = Peer(identity: identity, status: .notConnected)
        let connectedPeer = Peer(identity: identity, status: .connected)
        let otherPeer = Peer(identity: PeerIdentity(identifier: "other", displayName: "Other"), status: .notConnected)
        let foundExpectation = self.expectation(description: "Model found peer")
        let connectedExpectation = self.expectation(description: "Model updated peer status")
        foundExpectation.assertForOverFulfill = false
        connectedExpectation.assertForOverFulfill = false
        let model = PeerBrowserModel(manager: manager) { peers in
            if peers.first?.status == .connected {
                connectedExpectation.fulfill()
            } else if peers.first == foundPeer {
                foundExpectation.fulfill()
            }
        }

        model.startObserving()
        await startBrowsingOnly(manager)
        await harness.browserObserver?.updateAsync(.foundPeer(foundPeer, discoveryInfo: nil))
        await fulfillment(of: [foundExpectation], timeout: 1)
        await harness.sessionObserver?.updateAsync(.devicesChanged(peer: connectedPeer))

        await fulfillment(of: [connectedExpectation], timeout: 1)
        XCTAssertEqual(model.discoveredPeers.first?.status, .connected)

        await harness.browserObserver?.updateAsync(.foundPeer(otherPeer, discoveryInfo: nil))
        await shortAsyncDelay()
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

    internal func testStopObservingRemovesModelListener() async {
        let harness = PeerBrowserModelHarness()
        let manager = makeManager(harness: harness)
        let listenerKey = "PeerBrowserModelTests.stopObserving"
        let model = PeerBrowserModel(manager: manager, listenerKey: listenerKey)
        let peer = Peer(identity: PeerIdentity(identifier: "remote", displayName: "Remote"), status: .notConnected)

        model.startObserving()
        await startBrowsingOnly(manager)
        model.stopObserving()
        await manager.removeListenerForKeyAsync(listenerKey)
        await harness.browserObserver?.updateAsync(.foundPeer(peer, discoveryInfo: nil))

        await shortAsyncDelay()
        XCTAssertTrue(model.discoveredPeers.isEmpty)
    }

    private func startBrowsingOnly(_ manager: PeerConnectionManager) async {
        await withCheckedContinuation { continuation in
            manager.startBrowsingOnly {
                continuation.resume()
            }
        }
    }

    private func shortAsyncDelay() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    private func makeManager(harness: PeerBrowserModelHarness) -> PeerConnectionManager {
        return PeerConnectionManager(serviceType: "browser-model",
            connectionType: .custom,
            displayName: "Local",
            transportFactory: harness.factory)
    }
}
