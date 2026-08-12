//
//  PeerSecurityConfigurationTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 6/3/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
import MultipeerConnectivity
@testable import PeerConnectivity

// MARK: - PeerSecurityConfigurationTests

class PeerSecurityConfigurationTests: XCTestCase {

    // MARK: - Configuration Tests

    func testDefaultSecurityConfigurationMapsToBackwardCompatibleValues() {
        let configuration = PeerSecurityConfiguration.default

        XCTAssertEqual(configuration.encryptionPreference, .optional)
        XCTAssertNil(configuration.securityIdentity)

        switch configuration.certificatePolicy {
        case .acceptAll:
            break
        default:
            XCTFail("Default certificate policy should accept all certificates")
        }
    }

    func testEncryptedSecurityConfigurationRequiresEncryption() {
        let configuration = PeerSecurityConfiguration.encrypted

        XCTAssertEqual(configuration.encryptionPreference, .required)
        XCTAssertNil(configuration.securityIdentity)

        switch configuration.certificatePolicy {
        case .acceptAll:
            break
        default:
            XCTFail("Encrypted convenience configuration should preserve accept-all certificate behavior")
        }
    }

    func testManagerStoresSecurityConfiguration() {
        let configuration = PeerSecurityConfiguration.encrypted
        let manager = PeerConnectionManager(serviceType: "security-test", securityConfiguration: configuration)

        XCTAssertEqual(manager.securityConfiguration.encryptionPreference, .required)
        XCTAssertNil(manager.securityConfiguration.securityIdentity)
        manager.stop()
    }

    func testManagerDefaultsToAcceptAllInvitationPolicy() {
        let manager = PeerConnectionManager(serviceType: "invite-default")

        switch manager.invitationPolicy {
        case .acceptAll:
            break
        default:
            XCTFail("Default invitation policy should accept all invitations")
        }
        manager.stop()
    }

    func testManagerStoresInvitationPolicy() {
        let manager = makeManager(invitationPolicy: .rejectAll)

        switch manager.invitationPolicy {
        case .rejectAll:
            break
        default:
            XCTFail("Manager should store the configured invitation policy")
        }
        manager.stop()
    }

    // MARK: - Certificate Policy Tests

    func testAcceptAllCertificatePolicyAcceptsMissingCertificate() {
        let manager = makeManager(policy: .acceptAll)
        let result = evaluateCertificatePolicy(manager: manager, certificate: nil)

        XCTAssertEqual(result, true)
        manager.stop()
    }

    func testRejectAllCertificatePolicyRejectsCertificate() {
        let manager = makeManager(policy: .rejectAll)
        let result = evaluateCertificatePolicy(manager: manager, certificate: ["certificate"])

        XCTAssertEqual(result, false)
        manager.stop()
    }

    func testRequireCertificatePolicyRejectsMissingCertificate() {
        let manager = makeManager(policy: .requireCertificate)
        let result = evaluateCertificatePolicy(manager: manager, certificate: nil)

        XCTAssertEqual(result, false)
        manager.stop()
    }

    func testRequireCertificatePolicyRejectsEmptyCertificate() {
        let manager = makeManager(policy: .requireCertificate)
        let result = evaluateCertificatePolicy(manager: manager, certificate: [])

        XCTAssertEqual(result, false)
        manager.stop()
    }

    func testRequireCertificatePolicyAcceptsPresentCertificate() {
        let manager = makeManager(policy: .requireCertificate)
        let result = evaluateCertificatePolicy(manager: manager, certificate: ["certificate"])

        XCTAssertEqual(result, true)
        manager.stop()
    }

    func testCustomCertificatePolicyReceivesPeerAndCertificateAndControlsAcceptance() {
        var receivedPeer: Peer?
        var receivedCertificate: [Any]?
        let expectedCertificate: [Any] = ["certificate"]
        let manager = makeManager(policy: .custom { peer, certificate, handler in
            receivedPeer = peer
            receivedCertificate = certificate
            handler(false)
        })

        let result = evaluateCertificatePolicy(manager: manager, certificate: expectedCertificate)

        XCTAssertEqual(result, false)
        XCTAssertEqual(receivedPeer, manager.peer)
        XCTAssertEqual(receivedCertificate?.first as? String, "certificate")
        manager.stop()
    }

    func testCertificatePolicyStillEmitsCompatibilityEvent() async throws {
        let manager = makeManager(policy: .acceptAll)
        var result: Bool?
        var receivedPeer: Peer?
        var receivedCertificate: [Any]?
        let expectedCertificate: [Any] = ["certificate"]

        manager.listenOn({ event in
            switch event {
            case .receivedCertificate(let peer, let certificate, let handler):
                receivedPeer = peer
                receivedCertificate = certificate
                handler(false)
            default: break
            }
        }, performListenerInBackground: true, withKey: "certificate-compatibility")
        try await Task.sleep(nanoseconds: 10_000_000)

        manager.handleCertificate(peer: manager.peer, certificate: expectedCertificate) { accepted in
            result = accepted
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(result, true)
        XCTAssertEqual(receivedPeer, manager.peer)
        XCTAssertEqual(receivedCertificate?.first as? String, "certificate")
        manager.stop()
    }

    // MARK: - Invitation Policy Tests

    func testAcceptAllInvitationPolicyAcceptsInvitation() {
        let manager = makeManager(invitationPolicy: .acceptAll)
        let result = evaluateInvitationPolicy(manager: manager, context: nil)

        XCTAssertEqual(result, true)
        manager.stop()
    }

    func testRejectAllInvitationPolicyRejectsInvitation() {
        let manager = makeManager(invitationPolicy: .rejectAll)
        let result = evaluateInvitationPolicy(manager: manager, context: nil)

        XCTAssertEqual(result, false)
        manager.stop()
    }

    func testAutomaticAcceptAllInvitationPolicyStillEmitsCompatibilityEvent() async throws {
        let manager = makeManager(invitationPolicy: .acceptAll)
        var result: Bool?
        var receivedPeer: Peer?
        let expectedContext = "automatic".data(using: .utf8)

        manager.listenOn({ event in
            switch event {
            case .receivedInvitation(let peer, let context, let invitationHandler):
                receivedPeer = peer
                XCTAssertEqual(context, expectedContext)
                invitationHandler(false)
            default: break
            }
        }, performListenerInBackground: true, withKey: "automatic-invitation-compatibility")
        try await Task.sleep(nanoseconds: 10_000_000)

        manager.handleInvitation(peer: manager.peer, context: expectedContext) { accepted, _ in
            result = accepted
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(result, true)
        XCTAssertEqual(receivedPeer, manager.peer)
        manager.stop()
    }

    func testCustomInvitationPolicyReceivesPeerAndContextAndControlsAcceptance() {
        var receivedPeer: Peer?
        var receivedContext: Data?
        let expectedContext = "pairing".data(using: .utf8)
        let manager = makeManager(invitationPolicy: .custom { peer, context in
            receivedPeer = peer
            receivedContext = context
            return false
        })

        let result = evaluateInvitationPolicy(manager: manager, context: expectedContext)

        XCTAssertEqual(result, false)
        XCTAssertEqual(receivedPeer, manager.peer)
        XCTAssertEqual(receivedContext, expectedContext)
        manager.stop()
    }

    func testManualInvitationPolicyPreservesReceivedInvitationEvent() async throws {
        let manager = makeManager(invitationPolicy: .manual)
        var receivedPeer: Peer?
        var receivedContext: Data?
        let expectedContext = "manual".data(using: .utf8)

        manager.listenOn({ event in
            switch event {
            case .receivedInvitation(let peer, let context, let invitationHandler):
                receivedPeer = peer
                receivedContext = context
                invitationHandler(false)
            default: break
            }
        }, performListenerInBackground: true, withKey: "manual-invitation")
        try await Task.sleep(nanoseconds: 10_000_000)

        var result: Bool?
        manager.handleInvitation(peer: manager.peer, context: expectedContext) { accepted, _ in
            result = accepted
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(result, false)
        XCTAssertEqual(receivedPeer, manager.peer)
        XCTAssertEqual(receivedContext, expectedContext)
        manager.stop()
    }

    func testCustomConnectionTypePreservesReceivedInvitationEvent() async throws {
        let manager = makeManager(invitationPolicy: .acceptAll, connectionType: .custom)
        var receivedInvitation = false

        manager.listenOn({ event in
            switch event {
            case .receivedInvitation(_, _, let invitationHandler):
                receivedInvitation = true
                invitationHandler(false)
            default: break
            }
        }, performListenerInBackground: true, withKey: "custom-invitation")
        try await Task.sleep(nanoseconds: 10_000_000)

        var result: Bool?
        manager.handleInvitation(peer: manager.peer, context: nil) { accepted, _ in
            result = accepted
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(receivedInvitation, true)
        XCTAssertEqual(result, false)
        manager.stop()
    }

    // MARK: - Helper Methods

    /// Builds a manager with a specific certificate policy.
    private func makeManager(policy: PeerCertificatePolicy) -> PeerConnectionManager {
        let configuration = PeerSecurityConfiguration(
            encryptionPreference: .optional,
            securityIdentity: nil,
            certificatePolicy: policy
        )
        return PeerConnectionManager(
            serviceType: "sec-\(UUID().uuidString.prefix(8).lowercased())",
            securityConfiguration: configuration
        )
    }

    /// Builds a manager with a specific invitation policy.
    private func makeManager(invitationPolicy: PeerInvitationPolicy,
                             connectionType: PeerConnectionType = .automatic) -> PeerConnectionManager {
        return PeerConnectionManager(
            serviceType: "inv-\(UUID().uuidString.prefix(8).lowercased())",
            connectionType: connectionType,
            invitationPolicy: invitationPolicy
        )
    }

    /// Applies the manager certificate policy and returns the resulting handler value.
    private func evaluateCertificatePolicy(manager: PeerConnectionManager, certificate: [Any]?) -> Bool? {
        var result: Bool?
        manager.handleCertificate(peer: manager.peer, certificate: certificate) { accepted in
            result = accepted
        }
        return result
    }

    /// Applies the manager invitation policy and returns the resulting handler value.
    private func evaluateInvitationPolicy(manager: PeerConnectionManager, context: Data?) -> Bool? {
        var result: Bool?
        manager.handleInvitation(peer: manager.peer, context: context) { accepted, _ in
            result = accepted
        }
        return result
    }
}
