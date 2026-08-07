//
//  NetworkPeerLoopbackTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 8/6/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
@testable import PeerConnectivity

private struct LoopbackMessage : PeerMessage, Equatable {
    internal static let messageType = "loopback-message"
    internal let text : String
}

final class NetworkPeerLoopbackTests : XCTestCase {

    internal func testNetworkBackendDiscoversConnectsAndExchangesMessage() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let serviceType = "pctest-\(UUID().uuidString.prefix(8).lowercased())"
        let security = PeerConnectionNetworkSecurity.preSharedKey(Data("shared-loopback-secret".utf8))
        let alice = PeerConnectionManager(serviceType: serviceType,
            connectionType: .automatic,
            displayName: "Alice",
            backend: .networkFramework,
            networkSecurity: security,
            transportFactory: .networkFramework(security: security))
        let bob = PeerConnectionManager(serviceType: serviceType,
            connectionType: .automatic,
            displayName: "Bob",
            backend: .networkFramework,
            networkSecurity: security,
            transportFactory: .networkFramework(security: security))
        let aliceFoundBob = expectation(description: "Alice found Bob")
        let bobFoundAlice = expectation(description: "Bob found Alice")
        let aliceConnected = expectation(description: "Alice connected")
        let bobConnected = expectation(description: "Bob connected")
        let bobReceivedMessage = expectation(description: "Bob received Alice message")

        alice.listenOn({ event in
            switch event {
            case .foundPeer(let peer) where peer.displayName == "Bob":
                aliceFoundBob.fulfill()
            case .devicesChanged(peer: let peer, connectedPeers: let connectedPeers)
                where peer.displayName == "Bob" && connectedPeers.contains(where: { $0.displayName == "Bob" }):
                aliceConnected.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "alice-events")

        bob.listenOn({ event in
            switch event {
            case .foundPeer(let peer) where peer.displayName == "Alice":
                bobFoundAlice.fulfill()
            case .devicesChanged(peer: let peer, connectedPeers: let connectedPeers)
                where peer.displayName == "Alice" && connectedPeers.contains(where: { $0.displayName == "Alice" }):
                bobConnected.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "bob-events")

        bob.observeMessages(ofType: LoopbackMessage.self, forKey: "bob-message") { message, peer in
            XCTAssertEqual(peer.displayName, "Alice")
            XCTAssertEqual(message, LoopbackMessage(text: "hello"))
            bobReceivedMessage.fulfill()
        }

        bob.start()
        alice.start()

        wait(for: [aliceFoundBob, bobFoundAlice, aliceConnected, bobConnected], timeout: 15)
        alice.sendMessage(LoopbackMessage(text: "hello"), toPeers: alice.connectedPeers)
        wait(for: [bobReceivedMessage], timeout: 5)

        alice.stop()
        bob.stop()
    }

    internal func testNetworkBackendRejectsMismatchedPreSharedKeys() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let serviceType = "pctest-\(UUID().uuidString.prefix(8).lowercased())"
        let aliceSecurity = PeerConnectionNetworkSecurity.preSharedKey(Data("alice-secret".utf8))
        let bobSecurity = PeerConnectionNetworkSecurity.preSharedKey(Data("bob-secret".utf8))
        let alice = PeerConnectionManager(serviceType: serviceType,
            connectionType: .automatic,
            displayName: "Alice",
            backend: .networkFramework,
            networkSecurity: aliceSecurity,
            transportFactory: .networkFramework(security: aliceSecurity))
        let bob = PeerConnectionManager(serviceType: serviceType,
            connectionType: .automatic,
            displayName: "Bob",
            backend: .networkFramework,
            networkSecurity: bobSecurity,
            transportFactory: .networkFramework(security: bobSecurity))
        let unexpectedAliceConnection = expectation(description: "Alice should not connect")
        let unexpectedBobConnection = expectation(description: "Bob should not connect")
        unexpectedAliceConnection.isInverted = true
        unexpectedBobConnection.isInverted = true

        alice.listenOn({ event in
            switch event {
            case .devicesChanged(peer: let peer, connectedPeers: let connectedPeers)
                where peer.displayName == "Bob" && connectedPeers.contains(where: { $0.displayName == "Bob" }):
                unexpectedAliceConnection.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "alice-events")

        bob.listenOn({ event in
            switch event {
            case .devicesChanged(peer: let peer, connectedPeers: let connectedPeers)
                where peer.displayName == "Alice" && connectedPeers.contains(where: { $0.displayName == "Alice" }):
                unexpectedBobConnection.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "bob-events")

        bob.start()
        alice.start()

        wait(for: [unexpectedAliceConnection, unexpectedBobConnection], timeout: 5)

        alice.stop()
        bob.stop()
    }
}
