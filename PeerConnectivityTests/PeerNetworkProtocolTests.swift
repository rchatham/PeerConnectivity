//
//  PeerNetworkProtocolTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import XCTest
import Network
@testable import PeerConnectivity

private enum HandshakeEncodingTestError : Error {
    case failed
}

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

    internal func testDiscoveryInfoTxtRecordRoundTrip() {
        let identity = PeerIdentity(identifier: "peer-1", displayName: "Remote Peer")
        let discoveryInfo = PeerNetworkDiscoveryInfo(identity: identity)

        let decoded = PeerNetworkDiscoveryInfo(txtRecordDictionary: discoveryInfo.txtRecordDictionary)

        XCTAssertEqual(decoded, discoveryInfo)
    }

    internal func testDiscoveryInfoConstrainsTxtRecordValueLengths() {
        let identity = PeerIdentity(identifier: String(repeating: "a", count: 400),
            displayName: String(repeating: "b", count: 400))
        let discoveryInfo = PeerNetworkDiscoveryInfo(identity: identity)

        XCTAssertLessThanOrEqual(discoveryInfo.identity.identifier.count, 180)
        XCTAssertLessThanOrEqual(discoveryInfo.identity.displayName.count, 255)
    }

    internal func testDiscoveryInfoRejectsMalformedTxtRecord() {
        XCTAssertNil(PeerNetworkDiscoveryInfo(txtRecordDictionary: [:]))
        XCTAssertNil(PeerNetworkDiscoveryInfo(txtRecordDictionary: [
            "pc-id": "peer-1",
            "pc-name": "Remote Peer",
            "pc-v": "999",
        ]))
        XCTAssertNil(PeerNetworkDiscoveryInfo(txtRecordDictionary: [
            "pc-id": "",
            "pc-name": "Remote Peer",
            "pc-v": String(PeerNetworkHandshake.currentProtocolVersion),
        ]))
    }

    @available(iOS 13.0, macOS 10.15, *)
    internal func testHandshakeEncodingFailureCompletesWithError() {
        let connection = NetworkPeerConnection(
            endpoint: .hostPort(host: "localhost", port: 9),
            handshakeEncoder: { _ in throw HandshakeEncodingTestError.failed }
        )
        let handshake = PeerNetworkHandshake(
            identity: PeerIdentity(identifier: "peer-1", displayName: "Remote Peer")
        )
        var receivedError : NWError?

        connection.sendHandshake(handshake) { error in
            receivedError = error
        }

        guard case .posix(.EINVAL)? = receivedError else {
            return XCTFail("Expected EINVAL for a handshake encoding failure")
        }
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

    internal func testFrameDecodeRejectsOversizedPayloadLength() {
        let oversizedLength = UInt32(PeerNetworkFrame.maxPayloadLength + 1)
        let data = frameHeader(kind: .data, payloadLength: oversizedLength)

        XCTAssertNil(PeerNetworkFrame.decode(data))
    }

    internal func testFrameDecoderClearsOversizedFrame() {
        let oversizedLength = UInt32(PeerNetworkFrame.maxPayloadLength + 1)
        let validFrame = PeerNetworkFrame(kind: .data, payload: Data([1, 2, 3]))
        var decoder = PeerNetworkFrameDecoder()

        XCTAssertTrue(decoder.append(frameHeader(kind: .data, payloadLength: oversizedLength)).isEmpty)
        XCTAssertEqual(decoder.append(validFrame.encoded()), [validFrame])
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

    internal func testFrameDecoderHandlesManyCoalescedFramesBeforePartialFrame() {
        let frames = (0..<10_000).map { index in
            return PeerNetworkFrame(kind: .data, payload: Data([UInt8(index % 251)]))
        }
        let partialFrame = PeerNetworkFrame(kind: .handshake, payload: Data([1, 2, 3, 4]))
        let partialData = partialFrame.encoded()
        let splitIndex = partialData.index(partialData.startIndex, offsetBy: 3)
        var encoded = frames.reduce(into: Data()) { data, frame in
            data.append(frame.encoded())
        }
        encoded.append(partialData[..<splitIndex])
        var decoder = PeerNetworkFrameDecoder()

        XCTAssertEqual(decoder.append(encoded), frames)
        XCTAssertEqual(decoder.append(Data(partialData[splitIndex...])), [partialFrame])
    }

    internal func testFrameDecoderPreservesFrameKind() {
        let frame = PeerNetworkFrame(kind: .handshake, payload: Data([7, 8, 9]))
        var decoder = PeerNetworkFrameDecoder()

        let decoded = decoder.append(frame.encoded())

        XCTAssertEqual(decoded.first?.kind, .handshake)
        XCTAssertEqual(decoded.first?.payload, frame.payload)
    }

    private func frameHeader(kind: PeerNetworkFrameKind, payloadLength: UInt32) -> Data {
        var data = Data()
        data.append(kind.rawValue)
        var length = payloadLength.bigEndian
        withUnsafeBytes(of: &length) { bytes in
            data.append(contentsOf: bytes)
        }
        return data
    }
}
