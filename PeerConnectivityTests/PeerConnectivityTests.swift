//
//  PeerConnectivityTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 6/9/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import XCTest
import MultipeerConnectivity
@testable import PeerConnectivity

class PeerConnectivityTests: XCTestCase {

    var pcm : PeerConnectionManager?

    override func tearDown() {
        pcm?.stop()
        pcm = nil
        super.tearDown()
    }

    func testManagerInitialState() {
        let manager = PeerConnectionManager(serviceType: "test-service", displayName: "Unit Tester")
        pcm = manager

        XCTAssertEqual(manager.peer.displayName, "Unit Tester")
        XCTAssertTrue(manager.connectedPeers.isEmpty)
        XCTAssertTrue(manager.foundPeers.isEmpty)
        XCTAssertEqual(manager.peerServiceType, "test-service")
        assertStatus(manager.peer.status, is: .currentUser)
    }

    func testListenOnDoesNotReplayReadyEventInBackgroundMode() async throws {
        let manager = PeerConnectionManager(serviceType: "test-listen", displayName: "Listener")
        let expectation = expectation(description: "Ready event is not replayed")
        expectation.isInverted = true

        manager.listenOn({ event in
            if case .ready = event {
                expectation.fulfill()
            }
        }, performListenerInBackground: true, withKey: "ready")

        await fulfillment(of: [expectation], timeout: 0.1)
        await manager.removeListenerForKeyAsync("ready")
        manager.stop()
    }

    func testRemovedListenerDoesNotReceiveLaterEvents() async throws {
        let manager = PeerConnectionManager(serviceType: "test-remove", displayName: "Listener")
        pcm = manager
        let removedExpectation = expectation(description: "Removed listener receives no later events")
        removedExpectation.isInverted = true
        var eventCount = 0
        var didRemoveListener = false

        await manager.listenOnAsync({ _ in
            eventCount += 1
            if didRemoveListener { removedExpectation.fulfill() }
        }, performListenerInBackground: true, withKey: "removed")

        didRemoveListener = true
        await manager.removeListenerForKeyAsync("removed")
        manager.stop()
        await fulfillment(of: [removedExpectation], timeout: 0.1)

        XCTAssertEqual(eventCount, 0)
    }

    func testRemoveAllListenersRemovesRegisteredListeners() async throws {
        let manager = PeerConnectionManager(serviceType: "test-all", displayName: "Listener")
        pcm = manager
        let removedExpectation = expectation(description: "Removed listeners receive no later events")
        removedExpectation.isInverted = true
        var eventCount = 0
        var didRemoveListeners = false

        await manager.listenOnAsync({ _ in
            eventCount += 1
            if didRemoveListeners { removedExpectation.fulfill() }
        }, performListenerInBackground: true, withKey: "removed")

        didRemoveListeners = true
        await manager.removeAllListenersAsync()
        manager.stop()
        await fulfillment(of: [removedExpectation], timeout: 0.1)

        XCTAssertEqual(eventCount, 0)
    }

    private func assertStatus(_ status: Peer.Status, is expected: Peer.Status, file: StaticString = #file, line: UInt = #line) {
        switch (status, expected) {
        case (.currentUser, .currentUser),
             (.connected, .connected),
             (.connecting, .connecting),
             (.notConnected, .notConnected):
            return
        default:
            XCTFail("Expected status \(expected), got \(status)", file: file, line: line)
        }
    }

    func testManagerStoresDiscoveryInfo() {
        let discoveryInfo: PeerDiscoveryInfo = ["version": "1", "room": "lobby"]
        let manager = PeerConnectionManager(
            serviceType: "disc-test",
            displayName: "Discovery Tester",
            discoveryInfo: discoveryInfo
        )

        XCTAssertEqual(manager.discoveryInfo?["version"], "1")
        XCTAssertEqual(manager.discoveryInfo?["room"], "lobby")
        manager.stop()
    }

    func testAdvertiserAndAssisstantStoreDiscoveryInfo() {
        let discoveryInfo: PeerDiscoveryInfo = ["version": "1", "capability": "chat"]
        let observer = Observable<PeerSessionEvent>(.none)
        let producer = PeerSessionEventProducer(observer: observer)
        let session = PeerSession(peer: Peer(displayName: "discovery-test"), eventProducer: producer)
        let advertiserObserver = Observable<PeerAdvertiserEvent>(.none)
        let advertiserProducer = PeerAdvertiserEventProducer(observer: advertiserObserver)
        let assisstantObserver = Observable<PeerAdvertiserAssisstantEvent>(.none)
        let assisstantProducer = PeerAdvertiserAssisstantEventProducer(observer: assisstantObserver)

        let advertiser = PeerAdvertiser(
            session: session,
            serviceType: "disc-test",
            discoveryInfo: discoveryInfo,
            eventProducer: advertiserProducer
        )
        let assisstant = PeerAdvertiserAssisstant(
            session: session,
            serviceType: "disc-test",
            discoveryInfo: discoveryInfo,
            eventProducer: assisstantProducer
        )

        XCTAssertEqual(advertiser.discoveryInfo?["version"], "1")
        XCTAssertEqual(assisstant.discoveryInfo?["capability"], "chat")
    }

    func testBrowserEventPreservesDiscoveryInfo() async {
        let observer = Observable<PeerBrowserEvent>(.none)
        let producer = PeerBrowserEventProducer(observer: observer)
        let browser = MCNearbyServiceBrowser(peer: MCPeerID(displayName: "local"), serviceType: "disc-test")
        let remotePeerID = MCPeerID(displayName: "remote")
        let discoveryInfo: PeerDiscoveryInfo = ["version": "1", "room": "lobby"]
        var receivedDiscoveryInfo: PeerDiscoveryInfo?

        let expectation = expectation(description: "Found peer event received")
        await observer.addObserverAsync { event in
            switch event {
            case .foundPeer(_, let info):
                receivedDiscoveryInfo = info
                expectation.fulfill()
            default: break
            }
        }

        producer.browser(browser, foundPeer: remotePeerID, withDiscoveryInfo: discoveryInfo)
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(receivedDiscoveryInfo?["version"], "1")
        XCTAssertEqual(receivedDiscoveryInfo?["room"], "lobby")
    }

    func testPublicFoundPeerWithDiscoveryInfoEventCarriesMetadata() {
        let peer = Peer(displayName: "remote")
        let discoveryInfo: PeerDiscoveryInfo = ["version": "1"]
        let event = PeerConnectionEvent.foundPeerWithDiscoveryInfo(peer: peer, discoveryInfo: discoveryInfo)
        var receivedDiscoveryInfo: PeerDiscoveryInfo?

        switch event {
        case .foundPeerWithDiscoveryInfo(_, let info):
            receivedDiscoveryInfo = info
        default:
            XCTFail("Expected foundPeerWithDiscoveryInfo event")
        }

        XCTAssertEqual(receivedDiscoveryInfo?["version"], "1")
    }

    func testServiceTypeValidationAcceptsSupportedValues() {
        XCTAssertTrue(PeerConnectionManager.isValidServiceType("chat"))
        XCTAssertTrue(PeerConnectionManager.isValidServiceType("chat-1"))
        XCTAssertTrue(PeerConnectionManager.isValidServiceType("abcdefghijklmn1"))
    }

    func testServiceTypeValidationRejectsUnsupportedValues() {
        XCTAssertFalse(PeerConnectionManager.isValidServiceType(""))
        XCTAssertFalse(PeerConnectionManager.isValidServiceType("abcdefghijklmnop"))
        XCTAssertFalse(PeerConnectionManager.isValidServiceType("Chat"))
        XCTAssertFalse(PeerConnectionManager.isValidServiceType("chat_room"))
        XCTAssertFalse(PeerConnectionManager.isValidServiceType("chat.room"))
        XCTAssertFalse(PeerConnectionManager.isValidServiceType("-chat"))
        XCTAssertFalse(PeerConnectionManager.isValidServiceType("chat-"))
        XCTAssertFalse(PeerConnectionManager.isValidServiceType("ab--c"))
        XCTAssertFalse(PeerConnectionManager.isValidServiceType("123"))
    }

    func testDisplayNameValidationUsesUtf8ByteLength() {
        XCTAssertTrue(Peer.isValidDisplayName("peer"))
        XCTAssertTrue(Peer.isValidDisplayName(String(repeating: "a", count: 63)))
        XCTAssertFalse(Peer.isValidDisplayName(""))
        XCTAssertFalse(Peer.isValidDisplayName(String(repeating: "a", count: 64)))
        XCTAssertFalse(Peer.isValidDisplayName(String(repeating: "é", count: 32)))
    }

    func testPeerCanWrapExistingPeerIdentifier() {
        let peerID = MCPeerID(displayName: "remote")
        let peer = Peer(peerID: peerID, status: .notConnected)

        XCTAssertEqual(peer.displayName, "remote")
        XCTAssertEqual(peer.status, .notConnected)
    }
    
}
