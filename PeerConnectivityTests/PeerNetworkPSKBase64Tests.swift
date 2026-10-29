//
//  PeerNetworkPSKBase64Tests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 8/10/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
import Security
@testable import PeerConnectivity

class PeerNetworkPSKBase64Tests : XCTestCase {

    internal func testEmptyValueIsRejected() {
        XCTAssertEqual(PeerNetworkPSKBase64.decode(""), .failure(.empty))
    }

    internal func testMalformedValueIsRejected() {
        XCTAssertEqual(PeerNetworkPSKBase64.decode("not-base64!"), .failure(.malformed))
    }

    internal func testWhitespaceIsStrictlyRejected() {
        let value = Data(repeating: 1, count: 32).base64EncodedString() + "\n"
        XCTAssertEqual(PeerNetworkPSKBase64.decode(value), .failure(.containsWhitespace))
    }

    internal func testThirtyOneByteValueIsRejected() {
        let value = Data(repeating: 2, count: 31).base64EncodedString()
        XCTAssertEqual(
            PeerNetworkPSKBase64.decode(value),
            .failure(.tooShort(actualByteCount: 31, minimumByteCount: 32)))
    }

    internal func testThirtyTwoByteValueIsAccepted() {
        let data = Data(repeating: 3, count: 32)
        XCTAssertEqual(PeerNetworkPSKBase64.decode(data.base64EncodedString()), .success(data))
    }

    internal func testInvalidConfigurationMappingFailsClosed() {
        switch PeerNetworkPSKConfiguration.networkSecurity("") {
        case .success:
            XCTFail("Invalid TLS selection must not map to any network security configuration")
        case .failure(let error):
            XCTAssertEqual(error, .empty)
        }
    }

    internal func testValidConfigurationMapsToPreSharedKey() {
        let data = Data(repeating: 4, count: 32)
        XCTAssertEqual(
            PeerNetworkPSKConfiguration.networkSecurity(data.base64EncodedString()),
            .success(.preSharedKey(data)))
    }

    internal func testGeneratorRejectsZeroByteCountWithoutRequestingRandomBytes() {
        assertGeneratorRejectsByteCount(0)
    }

    internal func testGeneratorRejectsNegativeByteCountWithoutRequestingRandomBytes() {
        assertGeneratorRejectsByteCount(-1)
    }

    internal func testGeneratorRejectsThirtyOneByteCountWithoutRequestingRandomBytes() {
        assertGeneratorRejectsByteCount(31)
    }

    internal func testGeneratorAcceptsThirtyTwoByteCountWithInjectedRandomSuccess() {
        let result = PeerNetworkTestKeyGenerator.generateBase64(byteCount: 32) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 5)
            return errSecSuccess
        }
        guard case .success(let value) = result else { return XCTFail("Expected generated key") }
        XCTAssertEqual(PeerNetworkPSKBase64.decode(value), .success(Data(repeating: 5, count: 32)))
    }

    internal func testGeneratorFailureProducesNoKey() {
        let result = PeerNetworkTestKeyGenerator.generateBase64 { _ in -50 }
        XCTAssertEqual(result, .failure(PeerNetworkTestKeyGenerationError(status: -50)))
    }

    /// Verifies invalid byte counts fail closed before random generation or allocation.
    private func assertGeneratorRejectsByteCount(_ byteCount: Int, file: StaticString = #file, line: UInt = #line) {
        var didRequestRandomBytes = false
        let result = PeerNetworkTestKeyGenerator.generateBase64(byteCount: byteCount) { _ in
            didRequestRandomBytes = true
            return errSecSuccess
        }

        XCTAssertEqual(
            result,
            .failure(PeerNetworkTestKeyGenerationError(status: errSecParam)),
            file: file,
            line: line)
        XCTAssertFalse(didRequestRandomBytes, file: file, line: line)
    }
}
