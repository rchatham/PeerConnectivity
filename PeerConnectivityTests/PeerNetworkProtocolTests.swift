//
//  PeerNetworkProtocolTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import XCTest
@testable import PeerConnectivity

final class PeerNetworkProtocolTests : XCTestCase {

    internal func testBonjourServiceConvertsBareServiceType() {
        let service = PeerNetworkBonjourService(serviceType: "test-service")

        XCTAssertEqual(service.serviceType, "test-service")
        XCTAssertEqual(service.bonjourType, "_test-service._tcp")
    }

    internal func testBonjourServiceKeepsDNSServiceType() {
        let service = PeerNetworkBonjourService(serviceType: "_test-service._tcp")

        XCTAssertEqual(service.serviceType, "_test-service._tcp")
        XCTAssertEqual(service.bonjourType, "_test-service._tcp")
    }

    internal func testHandshakeRoundTrip() throws {
        let identity = PeerIdentity(identifier: "peer-1", displayName: "Remote Peer")
        let handshake = PeerNetworkHandshake(identity: identity)

        let data = try JSONEncoder().encode(handshake)
        let decoded = try JSONDecoder().decode(PeerNetworkHandshake.self, from: data)

        XCTAssertEqual(decoded, handshake)
        XCTAssertEqual(decoded.protocolVersion, PeerNetworkHandshake.currentProtocolVersion)
    }

    internal func testFrameRoundTrip() {
        let payload = Data([1, 2, 3, 4])
        let frame = PeerNetworkFrame(kind: .data, payload: payload)

        let decoded = PeerNetworkFrame.decode(frame.encoded())

        XCTAssertEqual(decoded, frame)
    }

    internal func testFrameDecodeRejectsIncompletePayload() {
        let frame = PeerNetworkFrame(kind: .data, payload: Data([1, 2, 3, 4]))
        let truncated = frame.encoded().dropLast()

        XCTAssertNil(PeerNetworkFrame.decode(Data(truncated)))
    }

    internal func testFrameDecodeRejectsUnknownKind() {
        let data = Data([255, 0, 0, 0, 0])

        XCTAssertNil(PeerNetworkFrame.decode(data))
    }

    internal func testFrameDecoderBuffersPartialFrame() {
        let frame = PeerNetworkFrame(kind: .handshake, payload: Data([1, 2, 3, 4]))
        let encoded = frame.encoded()
        let splitIndex = encoded.index(encoded.startIndex, offsetBy: 3)
        var decoder = PeerNetworkFrameDecoder()

        XCTAssertTrue(decoder.append(Data(encoded[..<splitIndex])).isEmpty)
        XCTAssertEqual(decoder.append(Data(encoded[splitIndex...])), [frame])
    }

    internal func testFrameDecoderEmitsCoalescedFrames() {
        let first = PeerNetworkFrame(kind: .handshake, payload: Data([1, 2, 3]))
        let second = PeerNetworkFrame(kind: .data, payload: Data([4, 5, 6]))
        var encoded = Data()
        encoded.append(first.encoded())
        encoded.append(second.encoded())
        var decoder = PeerNetworkFrameDecoder()

        XCTAssertEqual(decoder.append(encoded), [first, second])
    }

    internal func testFrameDecoderPreservesFrameKind() {
        let frame = PeerNetworkFrame(kind: .handshake, payload: Data([7, 8, 9]))
        var decoder = PeerNetworkFrameDecoder()

        let decoded = decoder.append(frame.encoded())

        XCTAssertEqual(decoded.first?.kind, .handshake)
        XCTAssertEqual(decoded.first?.payload, frame.payload)
    }
}
