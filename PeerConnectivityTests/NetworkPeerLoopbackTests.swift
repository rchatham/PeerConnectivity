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

private struct LargeLoopbackMessage : PeerMessage, Equatable {
    internal static let messageType = "large-loopback-message"
    internal let text : String
}

final class NetworkPeerLoopbackTests : XCTestCase {

    internal func testNetworkBackendDiscoversConnectsAndExchangesMessage() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let serviceType = makeServiceType()
        let security = makeSecurity()
        let alice = makeManager(serviceType: serviceType, displayName: "Alice", security: security)
        let bob = makeManager(serviceType: serviceType, displayName: "Bob", security: security)
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

    internal func testNetworkBackendExchangesMessagesBidirectionallyAndHandlesLargePayload() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let serviceType = makeServiceType()
        let security = makeSecurity()
        let alice = makeManager(serviceType: serviceType, displayName: "Alice", security: security)
        let bob = makeManager(serviceType: serviceType, displayName: "Bob", security: security)
        let aliceConnected = expectation(description: "Alice connected")
        let bobConnected = expectation(description: "Bob connected")
        let aliceReceivedReply = expectation(description: "Alice received Bob reply")
        let bobReceivedLargeMessage = expectation(description: "Bob received Alice large message")
        let largeText = String(repeating: "network-payload-", count: 4096)

        alice.listenOn({ event in
            switch event {
            case .devicesChanged(peer: let peer, connectedPeers: let connectedPeers)
                where peer.displayName == "Bob" && connectedPeers.contains(where: { $0.displayName == "Bob" }):
                aliceConnected.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "alice-events")

        bob.listenOn({ event in
            switch event {
            case .devicesChanged(peer: let peer, connectedPeers: let connectedPeers)
                where peer.displayName == "Alice" && connectedPeers.contains(where: { $0.displayName == "Alice" }):
                bobConnected.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "bob-events")

        alice.observeMessages(ofType: LoopbackMessage.self, forKey: "alice-reply") { message, peer in
            XCTAssertEqual(peer.displayName, "Bob")
            XCTAssertEqual(message, LoopbackMessage(text: "reply"))
            aliceReceivedReply.fulfill()
        }

        bob.observeMessages(ofType: LargeLoopbackMessage.self, forKey: "bob-large") { message, peer in
            XCTAssertEqual(peer.displayName, "Alice")
            XCTAssertEqual(message, LargeLoopbackMessage(text: largeText))
            bobReceivedLargeMessage.fulfill()
        }

        bob.start()
        alice.start()

        wait(for: [aliceConnected, bobConnected], timeout: 15)
        alice.sendMessage(LargeLoopbackMessage(text: largeText), toPeers: alice.connectedPeers)
        bob.sendMessage(LoopbackMessage(text: "reply"), toPeers: bob.connectedPeers)
        wait(for: [aliceReceivedReply, bobReceivedLargeMessage], timeout: 10)

        alice.stop()
        bob.stop()
    }

    internal func testNetworkBackendIsolatesDifferentServiceTypes() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let security = makeSecurity()
        let alice = makeManager(serviceType: makeServiceType(), displayName: "Alice", security: security)
        let bob = makeManager(serviceType: makeServiceType(), displayName: "Bob", security: security)
        let unexpectedAliceDiscovery = expectation(description: "Alice should not discover Bob")
        let unexpectedBobDiscovery = expectation(description: "Bob should not discover Alice")
        let unexpectedAliceConnection = expectation(description: "Alice should not connect to Bob")
        let unexpectedBobConnection = expectation(description: "Bob should not connect to Alice")
        unexpectedAliceDiscovery.isInverted = true
        unexpectedBobDiscovery.isInverted = true
        unexpectedAliceConnection.isInverted = true
        unexpectedBobConnection.isInverted = true

        alice.listenOn({ event in
            switch event {
            case .foundPeer(let peer) where peer.displayName == "Bob":
                unexpectedAliceDiscovery.fulfill()
            case .devicesChanged(peer: let peer, connectedPeers: let connectedPeers)
                where peer.displayName == "Bob" && connectedPeers.contains(where: { $0.displayName == "Bob" }):
                unexpectedAliceConnection.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "alice-events")

        bob.listenOn({ event in
            switch event {
            case .foundPeer(let peer) where peer.displayName == "Alice":
                unexpectedBobDiscovery.fulfill()
            case .devicesChanged(peer: let peer, connectedPeers: let connectedPeers)
                where peer.displayName == "Alice" && connectedPeers.contains(where: { $0.displayName == "Alice" }):
                unexpectedBobConnection.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "bob-events")

        bob.start()
        alice.start()

        wait(for: [unexpectedAliceDiscovery,
            unexpectedBobDiscovery,
            unexpectedAliceConnection,
            unexpectedBobConnection], timeout: 5)

        alice.stop()
        bob.stop()
    }

    internal func testNetworkBackendBroadcastsMessageToMultiplePeers() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let serviceType = makeServiceType()
        let security = makeSecurity()
        let alice = makeManager(serviceType: serviceType, displayName: "Alice", security: security)
        let bob = makeManager(serviceType: serviceType, displayName: "Bob", security: security)
        let charlie = makeManager(serviceType: serviceType, displayName: "Charlie", security: security)
        let aliceConnectedToBob = expectation(description: "Alice connected to Bob")
        let aliceConnectedToCharlie = expectation(description: "Alice connected to Charlie")
        let bobReceivedBroadcast = expectation(description: "Bob received Alice broadcast")
        let charlieReceivedBroadcast = expectation(description: "Charlie received Alice broadcast")
        let broadcast = LoopbackMessage(text: "broadcast")

        alice.listenOn({ event in
            switch event {
            case .devicesChanged(peer: let peer, connectedPeers: let connectedPeers)
                where peer.displayName == "Bob" && connectedPeers.contains(where: { $0.displayName == "Bob" }):
                aliceConnectedToBob.fulfill()
            case .devicesChanged(peer: let peer, connectedPeers: let connectedPeers)
                where peer.displayName == "Charlie" && connectedPeers.contains(where: { $0.displayName == "Charlie" }):
                aliceConnectedToCharlie.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "alice-events")

        bob.observeMessages(ofType: LoopbackMessage.self, forKey: "bob-broadcast") { message, peer in
            XCTAssertEqual(peer.displayName, "Alice")
            XCTAssertEqual(message, broadcast)
            bobReceivedBroadcast.fulfill()
        }

        charlie.observeMessages(ofType: LoopbackMessage.self, forKey: "charlie-broadcast") { message, peer in
            XCTAssertEqual(peer.displayName, "Alice")
            XCTAssertEqual(message, broadcast)
            charlieReceivedBroadcast.fulfill()
        }

        charlie.start()
        bob.start()
        alice.start()

        wait(for: [aliceConnectedToBob, aliceConnectedToCharlie], timeout: 20)
        alice.sendMessage(broadcast, toPeers: alice.connectedPeers)
        wait(for: [bobReceivedBroadcast, charlieReceivedBroadcast], timeout: 10)

        alice.stop()
        bob.stop()
        charlie.stop()
    }

    internal func testNetworkBackendRejectsMismatchedPreSharedKeys() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let serviceType = makeServiceType()
        let aliceSecurity = PeerConnectionNetworkSecurity.preSharedKey(Data("alice-secret".utf8))
        let bobSecurity = PeerConnectionNetworkSecurity.preSharedKey(Data("bob-secret".utf8))
        let alice = makeManager(serviceType: serviceType, displayName: "Alice", security: aliceSecurity)
        let bob = makeManager(serviceType: serviceType, displayName: "Bob", security: bobSecurity)
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

    private func makeServiceType() -> String {
        return "pctest-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func makeSecurity() -> PeerConnectionNetworkSecurity {
        return .preSharedKey(Data("shared-loopback-secret".utf8))
    }

    @available(iOS 13.0, macOS 10.15, *)
    private func makeManager(serviceType: ServiceType,
        displayName: String,
        security: PeerConnectionNetworkSecurity) -> PeerConnectionManager {
        return PeerConnectionManager(serviceType: serviceType,
            connectionType: .automatic,
            displayName: displayName,
            backend: .networkFramework,
            networkSecurity: security,
            transportFactory: .networkFramework(security: security))
    }
}
