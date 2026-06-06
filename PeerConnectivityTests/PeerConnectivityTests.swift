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
    
    var pcm: PeerConnectionManager?
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        pcm = PeerConnectionManager(serviceType: "test-service")
        pcm?.start()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        
        pcm?.stop()
        pcm = nil
    }
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    func testManagerStoresDiscoveryInfo() {
        let discoveryInfo: PeerDiscoveryInfo = ["version": "1", "room": "lobby"]
        let manager = PeerConnectionManager(serviceType: "disc-test", discoveryInfo: discoveryInfo)

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

    func testBrowserEventPreservesDiscoveryInfo() {
        let observer = Observable<PeerBrowserEvent>(.none)
        let producer = PeerBrowserEventProducer(observer: observer)
        let browser = MCNearbyServiceBrowser(peer: MCPeerID(displayName: "local"), serviceType: "disc-test")
        let remotePeerID = MCPeerID(displayName: "remote")
        let discoveryInfo: PeerDiscoveryInfo = ["version": "1", "room": "lobby"]
        var receivedDiscoveryInfo: PeerDiscoveryInfo?

        observer.addObserver { event in
            switch event {
            case .foundPeer(_, let info):
                receivedDiscoveryInfo = info
            default: break
            }
        }

        producer.browser(browser, foundPeer: remotePeerID, withDiscoveryInfo: discoveryInfo)

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
