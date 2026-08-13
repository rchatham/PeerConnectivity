//
//  PeerConnectionManagerTransportTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import XCTest
import MultipeerConnectivity
@testable import PeerConnectivity

private final class MockPeerSessionTransport : PeerSessionTransport {
    internal let peer : Peer
    internal var connectedPeers : [Peer] = []
    internal var startSessionCallCount = 0
    internal var stopSessionCallCount = 0
    internal var sentData : [(data: Data, peers: [Peer])] = []

    internal var multipeerSession : MCSession {
        XCTFail("Mock session should not expose a real MCSession")
        return MCSession(peer: MCPeerID(displayName: "unused"))
    }

    internal init(peer: Peer) {
        self.peer = peer
    }

    internal func startSession() {
        startSessionCallCount += 1
    }

    internal func stopSession() {
        stopSessionCallCount += 1
    }

    internal func sendData(_ data: Data, toPeers peers: [Peer]) {
        sentData.append((data: data, peers: peers))
    }

    internal func sendDataStream(_ streamName: String, toPeer peer: Peer) throws -> OutputStream {
        return OutputStream.toMemory()
    }

    internal func sendResourceAtURL(_ resourceURL: URL,
        withName name: String,
        toPeer peer: Peer,
        withCompletionHandler completion: ((Error?)->Void)?) -> Progress? {
        return nil
    }

    internal func nearbyConnectionDataForPeer(_ peer: Peer, withCompletionHandler completion: @escaping (Data?, Error?)->Void) {
        completion(nil, nil)
    }

    internal func connectPeer(_ peer: Peer, withNearbyConnectionData data: Data) {}

    internal func cancelConnectPeer(_ peer: Peer) {}
}

private final class MockPeerBrowserTransport : PeerBrowserTransport {
    internal var invitedPeers : [Peer] = []
    internal var startBrowsingCallCount = 0
    internal var stopBrowsingCallCount = 0

    internal func invitePeer(_ peer: Peer, withContext context: Data?, timeout: TimeInterval) {
        invitedPeers.append(peer)
    }

    internal func startBrowsing() {
        startBrowsingCallCount += 1
    }

    internal func stopBrowsing() {
        stopBrowsingCallCount += 1
    }
}

private final class MockPeerAdvertiserTransport : PeerAdvertiserTransport {
    internal var startAdvertisingCallCount = 0
    internal var stopAdvertisingCallCount = 0

    internal func startAdvertising() {
        startAdvertisingCallCount += 1
    }

    internal func stopAdvertising() {
        stopAdvertisingCallCount += 1
    }
}

private final class MockPeerAdvertiserAssisstantTransport : PeerAdvertiserAssisstantTransport {
    internal var startAdvertisingAssisstantCallCount = 0
    internal var stopAdvertisingAssisstantCallCount = 0

    internal func startAdvertisingAssisstant() {
        startAdvertisingAssisstantCallCount += 1
    }

    internal func stopAdvertisingAssisstant() {
        stopAdvertisingAssisstantCallCount += 1
    }
}

private final class PeerConnectionTransportHarness {
    internal var session : MockPeerSessionTransport?
    internal let browser = MockPeerBrowserTransport()
    internal let advertiser = MockPeerAdvertiserTransport()
    internal let advertiserAssisstant = MockPeerAdvertiserAssisstantTransport()
    internal var sessionObserver : Observable<PeerSessionEvent>?
    internal var browserObserver : Observable<PeerBrowserEvent>?
    internal var advertiserObserver : Observable<PeerAdvertiserEvent>?

    internal var factory : PeerConnectionTransportFactory {
        return PeerConnectionTransportFactory(
            makeSession: { [weak self] peer, _, observer in
                let session = MockPeerSessionTransport(peer: peer)
                self?.session = session
                self?.sessionObserver = observer
                return session
            },
            makeBrowser: { [weak self] _, _, observer in
                self?.browserObserver = observer
                return self!.browser
            },
            makeAdvertiser: { [weak self] _, _, _, observer in
                self?.advertiserObserver = observer
                return self!.advertiser
            },
            makeAdvertiserAssisstant: { [weak self] _, _, _, _ in
                return self!.advertiserAssisstant
            }
        )
    }
}

final class PeerConnectionManagerTransportTests : XCTestCase {

    internal func testStartBrowsingOnlyUsesInjectedSessionAndBrowser() async {
        let harness = PeerConnectionTransportHarness()
        let manager = PeerConnectionManager(serviceType: "test-service",
            displayName: "Local",
            transportFactory: harness.factory)

        await startBrowsingOnly(manager)

        XCTAssertEqual(harness.session?.startSessionCallCount, 1)
        XCTAssertEqual(harness.browser.startBrowsingCallCount, 1)
        XCTAssertEqual(harness.advertiser.startAdvertisingCallCount, 0)

        manager.stop()

        XCTAssertEqual(harness.session?.stopSessionCallCount, 1)
        XCTAssertEqual(harness.browser.stopBrowsingCallCount, 1)
        XCTAssertEqual(harness.advertiser.stopAdvertisingCallCount, 1)
        XCTAssertEqual(harness.advertiserAssisstant.stopAdvertisingAssisstantCallCount, 1)
    }

    internal func testSendDataUsesInjectedSession() {
        let harness = PeerConnectionTransportHarness()
        let manager = PeerConnectionManager(serviceType: "test-service",
            displayName: "Local",
            transportFactory: harness.factory)
        let data = Data([1, 2, 3])

        manager.sendData(data)

        XCTAssertEqual(harness.session?.sentData.count, 1)
        XCTAssertEqual(harness.session?.sentData.first?.data, data)
        XCTAssertEqual(harness.session?.sentData.first?.peers, [])
    }

    internal func testSessionDataEventForwardsReceivedData() async {
        let harness = PeerConnectionTransportHarness()
        let manager = PeerConnectionManager(serviceType: "test-service",
            displayName: "Local",
            transportFactory: harness.factory)
        let data = Data([4, 5, 6])
        let expectation = self.expectation(description: "Received data event")

        manager.listenOn({ event in
            switch event {
            case .receivedData(let peer, let receivedData):
                XCTAssertEqual(peer, manager.peer)
                XCTAssertEqual(receivedData, data)
                expectation.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "received-data")

        await startBrowsingOnly(manager)
        await harness.sessionObserver?.updateAsync(.didReceiveData(peer: manager.peer, data: data))

        await fulfillment(of: [expectation], timeout: 1)
    }

    internal func testBrowserEventForwardsFoundPeer() async {
        let harness = PeerConnectionTransportHarness()
        let manager = PeerConnectionManager(serviceType: "test-service",
            displayName: "Local",
            transportFactory: harness.factory)
        let expectation = self.expectation(description: "Found peer event")

        manager.listenOn({ event in
            switch event {
            case .foundPeer(let peer):
                XCTAssertEqual(peer, manager.peer)
                expectation.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "found-peer")

        await startBrowsingOnly(manager)
        await harness.browserObserver?.updateAsync(.foundPeer(manager.peer, discoveryInfo: nil))

        await fulfillment(of: [expectation], timeout: 1)
    }

    internal func testTransportEventAfterStopDoesNotEmitReceivedData() async {
        let harness = PeerConnectionTransportHarness()
        let manager = PeerConnectionManager(serviceType: "test-service",
            displayName: "Local",
            transportFactory: harness.factory)
        let expectation = self.expectation(description: "Received data event should not be emitted after stop")
        expectation.isInverted = true

        manager.listenOn({ event in
            switch event {
            case .receivedData:
                expectation.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "received-data")

        await startBrowsingOnly(manager)
        manager.stop()
        await harness.sessionObserver?.updateAsync(.didReceiveData(peer: manager.peer, data: Data([7, 8, 9])))

        await fulfillment(of: [expectation], timeout: 0.1)
    }

    internal func testTransportEventsRemainDeliveredAfterRefreshAndRapidRestarts() async {
        let harness = PeerConnectionTransportHarness()
        let manager = PeerConnectionManager(serviceType: "test-service",
            displayName: "Local",
            transportFactory: harness.factory)
        let receivedData = expectation(description: "New generation receives transport events")
        receivedData.expectedFulfillmentCount = 3

        manager.listenOn({ event in
            switch event {
            case .receivedData:
                receivedData.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "received-data")

        await startBrowsingOnly(manager)
        await refresh(manager)

        for _ in 0..<20 {
            manager.stop()
            manager.startBrowsingOnly()
        }
        manager.stop()
        await startBrowsingOnly(manager)

        for byte in UInt8(1)...3 {
            await harness.sessionObserver?.updateAsync(.didReceiveData(peer: manager.peer, data: Data([byte])))
            await Task.yield()
        }

        await fulfillment(of: [receivedData], timeout: 1)
    }

    private func startBrowsingOnly(_ manager: PeerConnectionManager) async {
        let expectation = expectation(description: "Manager started browsing only")
        manager.startBrowsingOnly {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1)
    }

    private func refresh(_ manager: PeerConnectionManager) async {
        let expectation = expectation(description: "Manager refreshed")
        manager.refresh {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1)
    }
}
