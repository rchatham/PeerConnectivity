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

    /// Applies the manager certificate policy and returns the resulting handler value.
    private func evaluateCertificatePolicy(manager: PeerConnectionManager, certificate: [Any]?) -> Bool? {
        var result: Bool?
        manager.handleCertificate(peer: manager.peer, certificate: certificate) { accepted in
            result = accepted
        }
        return result
    }
}
