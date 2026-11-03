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

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard ProcessInfo.processInfo.environment["CI"] == "true",
            ProcessInfo.processInfo.environment["PEERCONNECTIVITY_RUN_NETWORK_E2E"] != "1" else { return }
        throw XCTSkip("Network framework loopback tests run in the focused CI step")
    }

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
        defer { bob.stop() }
        alice.start()
        defer { alice.stop() }

        wait(for: [aliceFoundBob, bobFoundAlice, aliceConnected, bobConnected], timeout: 15)
        let aliceSendProcessed = expectation(description: "Alice send processed")
        let strangerSendFailed = expectation(description: "Send to unconnected peer failed")
        let stranger = Peer(displayName: "Stranger")
        XCTAssertNoThrow(try alice.sendMessage(LoopbackMessage(text: "hello"), toPeers: alice.connectedPeers) { failures in
            XCTAssertTrue(failures.isEmpty, "Sends to a connected peer must be processed without failures")
            aliceSendProcessed.fulfill()
        })
        alice.sendData(Data([1]), toPeers: [stranger]) { failures in
            guard case .peerNotConnected? = failures[stranger] as? PeerConnectionError else {
                return XCTFail("Targeted sends to unconnected peers must report peerNotConnected")
            }
            strangerSendFailed.fulfill()
        }
        wait(for: [bobReceivedMessage, aliceSendProcessed, strangerSendFailed], timeout: 5)
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
        defer { bob.stop() }
        alice.start()
        defer { alice.stop() }

        wait(for: [aliceConnected, bobConnected], timeout: 15)
        alice.sendMessage(LargeLoopbackMessage(text: largeText), toPeers: alice.connectedPeers)
        bob.sendMessage(LoopbackMessage(text: "reply"), toPeers: bob.connectedPeers)
        wait(for: [aliceReceivedReply, bobReceivedLargeMessage], timeout: 10)
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
        defer { bob.stop() }
        alice.start()
        defer { alice.stop() }

        wait(for: [unexpectedAliceDiscovery,
            unexpectedBobDiscovery,
            unexpectedAliceConnection,
            unexpectedBobConnection], timeout: 5)
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
        bobReceivedBroadcast.assertForOverFulfill = false
        charlieReceivedBroadcast.assertForOverFulfill = false

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
        defer { charlie.stop() }
        bob.start()
        defer { bob.stop() }
        alice.start()
        defer { alice.stop() }

        wait(for: [aliceConnectedToBob, aliceConnectedToCharlie], timeout: 20)
        for _ in 0..<3 {
            alice.sendMessage(broadcast, toPeers: alice.connectedPeers)
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        wait(for: [bobReceivedBroadcast, charlieReceivedBroadcast], timeout: 10)
    }

    internal func testNetworkBackendReconnectsAfterPeerRestarts() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let serviceType = makeServiceType()
        let security = makeSecurity()
        let alice = makeManager(serviceType: serviceType, displayName: "Alice", security: security)
        let firstBob = makeManager(serviceType: serviceType, displayName: "Bob", security: security)
        let aliceConnectedToFirstBob = expectation(description: "Alice connected to first Bob")
        let aliceDisconnectedFromFirstBob = expectation(description: "Alice disconnected from first Bob")
        let aliceConnectedToRestartedBob = expectation(description: "Alice connected to restarted Bob")
        let stateLock = NSLock()
        var didConnectFirstBob = false
        var didDisconnectFirstBob = false
        var didConnectRestartedBob = false

        alice.listenOn({ event in
            switch event {
            case .devicesChanged(peer: let peer, connectedPeers: let connectedPeers) where peer.displayName == "Bob":
                let isConnected = connectedPeers.contains(where: { $0.displayName == "Bob" })
                stateLock.lock()
                defer { stateLock.unlock() }
                if isConnected && !didConnectFirstBob {
                    didConnectFirstBob = true
                    aliceConnectedToFirstBob.fulfill()
                } else if !isConnected && didConnectFirstBob && !didDisconnectFirstBob {
                    didDisconnectFirstBob = true
                    aliceDisconnectedFromFirstBob.fulfill()
                } else if isConnected && didDisconnectFirstBob && !didConnectRestartedBob {
                    didConnectRestartedBob = true
                    aliceConnectedToRestartedBob.fulfill()
                }
            default: break
            }
        }, performListenerInBackground: true, withKey: "alice-events")

        var firstBobIsRunning = true
        firstBob.start()
        defer {
            if firstBobIsRunning {
                firstBob.stop()
            }
        }
        alice.start()
        defer { alice.stop() }
        wait(for: [aliceConnectedToFirstBob], timeout: 15)

        firstBob.stop()
        firstBobIsRunning = false
        wait(for: [aliceDisconnectedFromFirstBob], timeout: 15)

        let restartedBob = makeManager(serviceType: serviceType, displayName: "Bob", security: security)
        restartedBob.start()
        defer { restartedBob.stop() }
        wait(for: [aliceConnectedToRestartedBob], timeout: 20)
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
        defer { bob.stop() }
        alice.start()
        defer { alice.stop() }

        wait(for: [unexpectedAliceConnection, unexpectedBobConnection], timeout: 5)
    }

    internal func testNetworkBackendCertificateModeConnectsPinnedPeersAndExchangesMessage() throws {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let serviceType = makeServiceType()
        let alice = try makeCertificateManager(serviceType: serviceType, displayName: "Alice", identity: .alice, pinnedPeer: .bob)
        let bob = try makeCertificateManager(serviceType: serviceType, displayName: "Bob", identity: .bob, pinnedPeer: .alice)
        let aliceSawBobCertificate = expectation(description: "Alice observed Bob's certificate")
        let aliceConnected = expectation(description: "Alice connected")
        let bobConnected = expectation(description: "Bob connected")
        let bobReceivedMessage = expectation(description: "Bob received Alice message")
        aliceSawBobCertificate.assertForOverFulfill = false

        alice.listenOn({ event in
            switch event {
            case .receivedCertificate(peer: let peer, certificate: let certificate, handler: _)
                where peer.displayName == "Bob" && certificate?.isEmpty == false:
                aliceSawBobCertificate.fulfill()
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

        bob.observeMessages(ofType: LoopbackMessage.self, forKey: "bob-message") { message, peer in
            XCTAssertEqual(peer.displayName, "Alice")
            XCTAssertEqual(message, LoopbackMessage(text: "pinned"))
            bobReceivedMessage.fulfill()
        }

        bob.start()
        defer { bob.stop() }
        alice.start()
        defer { alice.stop() }

        wait(for: [aliceSawBobCertificate, aliceConnected, bobConnected], timeout: 15)
        alice.sendMessage(LoopbackMessage(text: "pinned"), toPeers: alice.connectedPeers)
        wait(for: [bobReceivedMessage], timeout: 5)
    }

    internal func testNetworkBackendCertificatePolicyRejectsUnpinnedPeer() throws {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let serviceType = makeServiceType()
        let mallory = try makeCertificateManager(serviceType: serviceType, displayName: "Mallory", identity: .mallory, pinnedPeer: .bob)
        let bob = try makeCertificateManager(serviceType: serviceType, displayName: "Bob", identity: .bob, pinnedPeer: .alice)
        let bobEvaluatedMallory = expectation(description: "Bob evaluated Mallory's certificate")
        let unexpectedConnection = expectation(description: "No peer should connect")
        bobEvaluatedMallory.assertForOverFulfill = false
        unexpectedConnection.isInverted = true
        unexpectedConnection.assertForOverFulfill = false

        bob.listenOn({ event in
            switch event {
            case .receivedCertificate(peer: let peer, certificate: _, handler: _) where peer.displayName == "Mallory":
                bobEvaluatedMallory.fulfill()
            case .devicesChanged(peer: _, connectedPeers: let connectedPeers) where !connectedPeers.isEmpty:
                unexpectedConnection.fulfill()
            default: break
            }
        }, performListenerInBackground: true, withKey: "bob-events")

        mallory.listenOn({ event in
            guard case .devicesChanged(peer: _, connectedPeers: let connectedPeers) = event, !connectedPeers.isEmpty else { return }
            unexpectedConnection.fulfill()
        }, performListenerInBackground: true, withKey: "mallory-events")

        bob.start()
        defer { bob.stop() }
        mallory.start()
        defer { mallory.stop() }

        wait(for: [bobEvaluatedMallory], timeout: 15)
        wait(for: [unexpectedConnection], timeout: 3)
    }

    internal func testNetworkBackendCertificateModeDoesNotConnectToUnauthenticatedPeer() throws {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let serviceType = makeServiceType()
        let alice = try makeCertificateManager(serviceType: serviceType, displayName: "Alice", identity: .alice, pinnedPeer: .bob)
        let bob = makeManager(serviceType: serviceType, displayName: "Bob", security: .unauthenticated)
        let unexpectedConnection = expectation(description: "Peers without certificates must not connect")
        unexpectedConnection.isInverted = true
        unexpectedConnection.assertForOverFulfill = false

        for manager in [alice, bob] {
            manager.listenOn({ event in
                guard case .devicesChanged(peer: _, connectedPeers: let connectedPeers) = event, !connectedPeers.isEmpty else { return }
                unexpectedConnection.fulfill()
            }, performListenerInBackground: true, withKey: "no-certificate-events")
        }

        bob.start()
        defer { bob.stop() }
        alice.start()
        defer { alice.stop() }

        wait(for: [unexpectedConnection], timeout: 5)
    }

    internal func testNetworkBackendPublishesAppDiscoveryInfo() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let serviceType = makeServiceType()
        let alice = PeerConnectionManager(serviceType: serviceType,
            connectionType: .custom,
            displayName: "Alice",
            discoveryInfo: ["app": "hermes", "session": "abc123"],
            backend: .networkFramework,
            networkSecurity: makeSecurity())
        let bob = makeManager(serviceType: serviceType, displayName: "Bob", security: makeSecurity(), connectionType: .custom)
        let bobSawInfo = expectation(description: "Bob received Alice's discovery info")
        bobSawInfo.assertForOverFulfill = false

        bob.listenOn({ event in
            guard case .foundPeerWithDiscoveryInfo(peer: let peer, discoveryInfo: let info) = event,
                peer.displayName == "Alice" else { return }
            XCTAssertEqual(info, ["app": "hermes", "session": "abc123"])
            bobSawInfo.fulfill()
        }, performListenerInBackground: true, withKey: "bob-discovery")

        bob.start()
        defer { bob.stop() }
        alice.start()
        defer { alice.stop() }

        wait(for: [bobSawInfo], timeout: 15)
    }

    internal func testNetworkBackendInvitationAcceptedWithContextConnects() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let harness = makeInvitationPair()
        let bobSawInvitation = expectation(description: "Bob saw Alice's invitation")
        let aliceConnected = expectation(description: "Alice connected")
        let bobConnected = expectation(description: "Bob connected")

        harness.onInvitation = { context, respond in
            XCTAssertEqual(context, Data("join".utf8))
            bobSawInvitation.fulfill()
            respond(true)
        }
        harness.onAliceConnected = { aliceConnected.fulfill() }
        harness.onBobConnected = { bobConnected.fulfill() }
        harness.start(context: Data("join".utf8), timeout: 10)
        defer { harness.stop() }

        wait(for: [bobSawInvitation, aliceConnected, bobConnected], timeout: 15)
    }

    internal func testNetworkBackendInvitationDeclinedNeverConnects() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let harness = makeInvitationPair()
        let bobSawInvitation = expectation(description: "Bob saw Alice's invitation")
        let unexpectedConnection = expectation(description: "Declined peers must not connect")
        unexpectedConnection.isInverted = true
        unexpectedConnection.assertForOverFulfill = false

        harness.onInvitation = { _, respond in
            bobSawInvitation.fulfill()
            respond(false)
        }
        harness.onAliceConnected = { unexpectedConnection.fulfill() }
        harness.onBobConnected = { unexpectedConnection.fulfill() }
        harness.start(context: nil, timeout: 10)
        defer { harness.stop() }

        wait(for: [bobSawInvitation], timeout: 15)
        wait(for: [unexpectedConnection], timeout: 3)
    }

    internal func testNetworkBackendUnansweredInvitationExpiresAndIgnoresLateAcceptance() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let harness = makeInvitationPair()
        let bobSawInvitation = expectation(description: "Bob saw Alice's invitation")
        let unexpectedConnection = expectation(description: "Expired invitations must not connect")
        unexpectedConnection.isInverted = true
        unexpectedConnection.assertForOverFulfill = false
        var lateResponse : ((Bool) -> Void)?

        harness.onInvitation = { _, respond in
            lateResponse = respond
            bobSawInvitation.fulfill()
        }
        harness.onAliceConnected = { unexpectedConnection.fulfill() }
        harness.onBobConnected = { unexpectedConnection.fulfill() }
        harness.start(context: nil, timeout: 1.5)
        defer { harness.stop() }

        wait(for: [bobSawInvitation], timeout: 15)
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        lateResponse?(true)
        wait(for: [unexpectedConnection], timeout: 2)
    }

    /// Alice and Bob in `.custom` mode: Alice invites Bob once she finds him; Bob's app decides.
    @available(iOS 13.0, macOS 10.15, *)
    private func makeInvitationPair() -> InvitationPair {
        let serviceType = makeServiceType()
        return InvitationPair(
            alice: makeManager(serviceType: serviceType, displayName: "Alice", security: makeSecurity(), connectionType: .custom),
            bob: makeManager(serviceType: serviceType, displayName: "Bob", security: makeSecurity(), connectionType: .custom))
    }

    private func makeServiceType() -> String {
        return "pctest-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func makeSecurity() -> PeerConnectionNetworkSecurity {
        return .preSharedKey(Data("shared-loopback-secret".utf8))
    }

    /// Builds a certificate-mode manager whose policy accepts only `pinnedPeer`'s leaf certificate.
    @available(iOS 13.0, macOS 10.15, *)
    private func makeCertificateManager(serviceType: ServiceType,
        displayName: String,
        identity: PeerNetworkCertificateFixtures.Name,
        pinnedPeer: PeerNetworkCertificateFixtures.Name) throws -> PeerConnectionManager {
        let pinnedCertificate = try PeerNetworkCertificateFixtures.certificateData(pinnedPeer)
        let configuration = PeerSecurityConfiguration(encryptionPreference: .required,
            securityIdentity: nil,
            certificatePolicy: .custom({ _, chain, decide in
                guard let leaf = chain?.first, CFGetTypeID(leaf as CFTypeRef) == SecCertificateGetTypeID() else {
                    return decide(false)
                }
                decide(SecCertificateCopyData(leaf as! SecCertificate) as Data == pinnedCertificate)
            }))
        return PeerConnectionManager(serviceType: serviceType,
            connectionType: .automatic,
            displayName: displayName,
            securityConfiguration: configuration,
            backend: .networkFramework,
            networkSecurity: .certificate(identity: try PeerNetworkCertificateFixtures.identity(identity)))
    }

    @available(iOS 13.0, macOS 10.15, *)
    private func makeManager(serviceType: ServiceType,
        displayName: String,
        security: PeerConnectionNetworkSecurity,
        connectionType: PeerConnectionType = .automatic) -> PeerConnectionManager {
        return PeerConnectionManager(serviceType: serviceType,
            connectionType: connectionType,
            displayName: displayName,
            backend: .networkFramework,
            networkSecurity: security,
            transportFactory: .networkFramework(security: security))
    }
}

private final class InvitationPair {
    internal let alice : PeerConnectionManager
    internal let bob : PeerConnectionManager
    internal var onInvitation : (Data?, @escaping (Bool) -> Void) -> Void = { _, _ in }
    internal var onAliceConnected : () -> Void = {}
    internal var onBobConnected : () -> Void = {}
    fileprivate let inviteLock = NSLock()
    fileprivate var hasInvited = false

    internal init(alice: PeerConnectionManager, bob: PeerConnectionManager) {
        self.alice = alice
        self.bob = bob
    }

    internal func start(context: Data?, timeout: TimeInterval) {
        alice.listenOn({ [weak self] event in
            guard let self = self else { return }
            switch event {
            case .foundPeer(let peer) where peer.displayName == "Bob":
                let shouldInvite : Bool = self.inviteLock.locked {
                    defer { self.hasInvited = true }
                    return !self.hasInvited
                }
                if shouldInvite {
                    self.alice.invitePeer(peer, withContext: context, timeout: timeout)
                }
            case .devicesChanged(peer: let peer, connectedPeers: let connectedPeers)
                where peer.displayName == "Bob" && connectedPeers.contains(where: { $0.displayName == "Bob" }):
                self.onAliceConnected()
            default: break
            }
        }, performListenerInBackground: true, withKey: "alice-invitation-events")

        bob.listenOn({ [weak self] event in
            switch event {
            case .receivedInvitation(peer: let peer, withContext: let context, invitationHandler: let respond)
                where peer.displayName == "Alice":
                self?.onInvitation(context, respond)
            case .devicesChanged(peer: let peer, connectedPeers: let connectedPeers)
                where peer.displayName == "Alice" && connectedPeers.contains(where: { $0.displayName == "Alice" }):
                self?.onBobConnected()
            default: break
            }
        }, performListenerInBackground: true, withKey: "bob-invitation-events")

        bob.start()
        alice.start()
    }

    internal func stop() {
        alice.stop()
        bob.stop()
    }
}
