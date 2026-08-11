//
//  PeerTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 6/9/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import MultipeerConnectivity
import XCTest
@testable import PeerConnectivity

class PeerTests: XCTestCase {

    // MARK: - Display Name

    func testLocalPeerUsesProvidedDisplayName() {
        let peer = Peer(displayName: "Local Tester")

        XCTAssertEqual(peer.displayName, "Local Tester")
        assertStatus(peer.status, is: .currentUser)
    }

    func testRemotePeerUsesMCPeerDisplayName() {
        let peerID = MCPeerID(displayName: "Remote Tester")
        let peer = Peer(peerID: peerID, status: .connected)

        XCTAssertEqual(peer.displayName, "Remote Tester")
        assertStatus(peer.status, is: .connected)
    }

    func testSanitizedDisplayNamePreservesValidName() {
        XCTAssertEqual(Peer.sanitizedDisplayName("Local Tester"), "Local Tester")
    }

    func testSanitizedDisplayNameUsesDeterministicFallbackForEmptyName() {
        XCTAssertEqual(Peer.sanitizedDisplayName(""), "Peer")
        XCTAssertEqual(Peer.sanitizedDisplayName("", fallback: ""), "Peer")
    }

    func testSanitizedDisplayNameTruncatesAtUnicodeScalarBoundary() {
        let displayName = String(repeating: "a", count: 61) + "é🙂suffix"
        let sanitized = Peer.sanitizedDisplayName(displayName)

        XCTAssertEqual(sanitized, String(repeating: "a", count: 61) + "é")
        XCTAssertEqual(sanitized.utf8.count, 63)
        XCTAssertTrue(Peer.isValidDisplayName(sanitized))
    }

    // MARK: - Equality

    func testPeersWithSamePeerIDAreEqualEvenWhenStatusDiffers() {
        let peerID = MCPeerID(displayName: "Shared")
        let connected = Peer(peerID: peerID, status: .connected)
        let connecting = Peer(peerID: peerID, status: .connecting)

        XCTAssertEqual(connected, connecting)
        XCTAssertEqual(connected.hashValue, connecting.hashValue)
    }

    func testPeersWithDifferentPeerIDsAreNotEqual() {
        let first = Peer(peerID: MCPeerID(displayName: "First"), status: .connected)
        let second = Peer(peerID: MCPeerID(displayName: "Second"), status: .connected)

        XCTAssertNotEqual(first, second)
    }

    func testPeerCanBeUsedInSet() {
        let peerID = MCPeerID(displayName: "Set Peer")
        let first = Peer(peerID: peerID, status: .connected)
        let second = Peer(peerID: peerID, status: .notConnected)
        let peers : Set<Peer> = [first, second]

        XCTAssertEqual(peers.count, 1)
        XCTAssertTrue(peers.contains(first))
    }

    // MARK: - Helpers

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
