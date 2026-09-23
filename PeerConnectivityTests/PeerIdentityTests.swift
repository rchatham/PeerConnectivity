//
//  PeerIdentityTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import XCTest
import MultipeerConnectivity
@testable import PeerConnectivity

final class PeerIdentityTests : XCTestCase {

    internal func testPeerIdentityArchivingIsDeterministicAndSecurelyDecodable() throws {
        let peerID = MCPeerID(displayName: "Remote Peer")

        let first = PeerIdentity(peerID: peerID)
        let second = PeerIdentity(peerID: peerID)
        let data = try XCTUnwrap(Data(base64Encoded: first.identifier))
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data)

        XCTAssertEqual(first.identifier, second.identifier)
        XCTAssertEqual(decoded, peerID)
    }

    internal func testPeerIdentityPreservesLegacyArchivedIdentifier() throws {
        let legacyIdentifier = "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGkCwwTFFUkbnVsbNMNDg8QERJUbmFtZVJpZFYkY2xhc3OAAhOVaDOwNeo/zoADWVRlc3QgUGVlctIVFhcYWiRjbGFzc25hbWVYJGNsYXNzZXNYTUNQZWVySUSiFxlYTlNPYmplY3QIERokKTI3SUxRU1heZWptdHZ/gYuQm6StsAAAAAAAAAEBAAAAAAAAABoAAAAAAAAAAAAAAAAAAAC5"
        let data = try XCTUnwrap(Data(base64Encoded: legacyIdentifier))
        let peerID = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data))

        XCTAssertEqual(PeerIdentity(peerID: peerID).identifier, legacyIdentifier)
        XCTAssertEqual(peerID.displayName, "Test Peer")
    }

    internal func testPeerDisplayNameUsesFrameworkNeutralIdentity() {
        let identity = PeerIdentity(identifier: "peer-1", displayName: "Remote Peer")
        let peer = Peer(identity: identity, status: .notConnected)

        XCTAssertEqual(peer.displayName, "Remote Peer")
    }

    internal func testPeerEqualityUsesIdentity() {
        let identity = PeerIdentity(identifier: "peer-1", displayName: "Remote Peer")
        let first = Peer(identity: identity, status: .connecting)
        let second = Peer(identity: identity, status: .connected)

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 1)
    }

    internal func testPeersWithSameDisplayNameAndDifferentIdentifiersAreDistinct() {
        let first = Peer(identity: PeerIdentity(identifier: "peer-1", displayName: "Remote Peer"), status: .connected)
        let second = Peer(identity: PeerIdentity(identifier: "peer-2", displayName: "Remote Peer"), status: .connected)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 2)
    }
}
