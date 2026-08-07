//
//  PeerConnectivityTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 6/9/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import XCTest
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

    func testListenOnImmediatelyReceivesReadyEventInBackgroundMode() {
        let manager = PeerConnectionManager(serviceType: "test-listen", displayName: "Listener")
        pcm = manager
        var didReceiveReady = false

        manager.listenOn({ event in
            switch event {
            case .ready:
                didReceiveReady = true
            default:
                break
            }
        }, performListenerInBackground: true, withKey: "ready")

        XCTAssertTrue(didReceiveReady)
    }

    func testRemovedListenerDoesNotReceiveLaterEvents() {
        let manager = PeerConnectionManager(serviceType: "test-remove", displayName: "Listener")
        pcm = manager
        var eventCount = 0

        manager.listenOn({ _ in
            eventCount += 1
        }, performListenerInBackground: true, withKey: "removed")
        manager.removeListenerForKey("removed")
        manager.stop()

        XCTAssertEqual(eventCount, 1)
    }

    func testRemoveAllListenersRemovesRegisteredListeners() {
        let manager = PeerConnectionManager(serviceType: "test-all", displayName: "Listener")
        pcm = manager
        var eventCount = 0

        manager.listenOn({ _ in
            eventCount += 1
        }, performListenerInBackground: true, withKey: "removed")
        manager.removeAllListeners()
        manager.stop()

        XCTAssertEqual(eventCount, 1)
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
}
