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

private final class BrowserModelSendableBox : @unchecked Sendable {
    internal let model : PeerBrowserModel

    internal init(_ model: PeerBrowserModel) {
        self.model = model
    }
}

private final class PeerBrowserModelHarness {
    internal let browser = BrowserModelMockBrowserTransport()
    internal var browserObserver : Observable<PeerBrowserEvent>?
    internal var sessionObserver : Observable<PeerSessionEvent>?

    internal var factory : PeerConnectionTransportFactory {
        return PeerConnectionTransportFactory(
            backend: .multipeerConnectivity,
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

    internal func testStopObservingClearsPeersNotifiesEmptyAndRemovesModelListener() async {
        let harness = PeerBrowserModelHarness()
        let manager = makeManager(harness: harness)
        let listenerKey = "PeerBrowserModelTests.stopObserving"
        let peer = Peer(identity: PeerIdentity(identifier: "remote", displayName: "Remote"), status: .notConnected)
        let foundExpectation = expectation(description: "Model found peer")
        let clearedExpectation = expectation(description: "Model cleared peers")
        var foundPeer = false
        let model = PeerBrowserModel(manager: manager, listenerKey: listenerKey) { peers in
            if peers == [peer] && !foundPeer {
                foundPeer = true
                foundExpectation.fulfill()
            } else if peers.isEmpty && foundPeer {
                clearedExpectation.fulfill()
            }
        }

        model.startObserving()
        await startBrowsingOnly(manager)
        await harness.browserObserver?.updateAsync(.foundPeer(peer, discoveryInfo: nil))
        await fulfillment(of: [foundExpectation], timeout: 1)
        XCTAssertEqual(model.discoveredPeers, [peer])

        model.stopObserving()
        XCTAssertTrue(model.discoveredPeers.isEmpty)
        await model.waitForPendingObservationTransition()
        await fulfillment(of: [clearedExpectation], timeout: 1)
        await harness.browserObserver?.updateAsync(.foundPeer(peer, discoveryInfo: nil))

        await shortAsyncDelay()
        XCTAssertTrue(model.discoveredPeers.isEmpty)
        let listenerCount = await manager.listenerCountAsync()
        XCTAssertEqual(listenerCount, 0)
    }

    internal func testStopWhileRegistrationIsBlockedDoesNotLeakListenerOrApplyEvents() async {
        let harness = PeerBrowserModelHarness()
        let manager = makeManager(harness: harness)
        let registrationStarted = DispatchSemaphore(value: 0)
        let allowRegistration = DispatchSemaphore(value: 0)
        let model = PeerBrowserModel(manager: manager,
            listenerKey: "PeerBrowserModelTests.blockedRegistration",
            lifecycleHooks: PeerBrowserModelLifecycleHooks(willRegisterListener: {
                registrationStarted.signal()
                allowRegistration.wait()
            }))
        let peer = Peer(identity: PeerIdentity(identifier: "remote", displayName: "Remote"), status: .notConnected)

        model.startObserving()
        XCTAssertEqual(registrationStarted.wait(timeout: .now() + 1), .success)
        model.stopObserving()
        allowRegistration.signal()
        await model.waitForPendingObservationTransition()
        await harness.browserObserver?.updateAsync(.foundPeer(peer, discoveryInfo: nil))

        await shortAsyncDelay()
        XCTAssertTrue(model.discoveredPeers.isEmpty)
        let listenerCount = await manager.listenerCountAsync()
        XCTAssertEqual(listenerCount, 0)
    }

    internal func testRepeatedRestartsDoNotReplayPreviouslyDiscoveredPeer() async {
        let harness = PeerBrowserModelHarness()
        let manager = makeManager(harness: harness)
        let priorPeer = Peer(identity: PeerIdentity(identifier: "prior", displayName: "Prior"), status: .notConnected)
        let futurePeer = Peer(identity: PeerIdentity(identifier: "future", displayName: "Future"), status: .notConnected)
        let priorPeerExpectation = expectation(description: "Model found prior peer")
        let futurePeerExpectation = expectation(description: "Model found future peer")
        var foundPriorPeer = false
        var foundFuturePeer = false
        let model = PeerBrowserModel(manager: manager,
            listenerKey: "PeerBrowserModelTests.repeatedRestarts") { peers in
            if peers.contains(priorPeer) && !foundPriorPeer {
                foundPriorPeer = true
                priorPeerExpectation.fulfill()
            }
            if peers == [futurePeer] && !foundFuturePeer {
                foundFuturePeer = true
                futurePeerExpectation.fulfill()
            }
        }

        model.startObserving()
        await startBrowsingOnly(manager)
        await harness.browserObserver?.updateAsync(.foundPeer(priorPeer, discoveryInfo: nil))
        await fulfillment(of: [priorPeerExpectation], timeout: 1)
        model.stopObserving()
        await model.waitForPendingObservationTransition()
        XCTAssertTrue(model.discoveredPeers.isEmpty)

        for _ in 0..<3 {
            model.startObserving()
            await model.waitForPendingObservationTransition()
            await shortAsyncDelay()
            XCTAssertTrue(model.discoveredPeers.isEmpty)

            model.stopObserving()
            await model.waitForPendingObservationTransition()
            XCTAssertTrue(model.discoveredPeers.isEmpty)
        }

        model.startObserving()
        await model.waitForPendingObservationTransition()
        await harness.browserObserver?.updateAsync(.lostPeer(priorPeer))
        await harness.browserObserver?.updateAsync(.foundPeer(futurePeer, discoveryInfo: nil))
        await fulfillment(of: [futurePeerExpectation], timeout: 1)
        XCTAssertEqual(model.discoveredPeers, [futurePeer])
    }

    internal func testRepeatedConcurrentStartStopCyclesLeaveNoListener() async {
        let harness = PeerBrowserModelHarness()
        let manager = makeManager(harness: harness)
        let model = PeerBrowserModel(manager: manager,
            listenerKey: "PeerBrowserModelTests.concurrentCycles")
        let modelBox = BrowserModelSendableBox(model)
        let operationsFinished = expectation(description: "Concurrent observation operations finished")

        DispatchQueue.global().async {
            DispatchQueue.concurrentPerform(iterations: 100) { iteration in
                if iteration.isMultiple(of: 2) {
                    modelBox.model.startObserving()
                } else {
                    modelBox.model.stopObserving()
                }
            }
            operationsFinished.fulfill()
        }

        await fulfillment(of: [operationsFinished], timeout: 2)
        model.stopObserving()
        await model.waitForPendingObservationTransition()

        let listenerCount = await manager.listenerCountAsync()
        XCTAssertEqual(listenerCount, 0)
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
