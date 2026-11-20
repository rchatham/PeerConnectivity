//
//  BluetoothSecureChannelTests.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
import Security
import PeerConnectivity
@testable import PeerConnectivityBluetooth

@available(iOS 13.0, macOS 10.15, *)
final class BluetoothSecureChannelTests : XCTestCase {

    // MARK: - Certificate mode

    func testCertificateChannelsOpenOnlyAfterThePeerSignatureVerifies() throws {
        let initiator = BluetoothSecureChannel(mode: .certificate(try credential(.alice)), direction: .outbound)
        let responder = BluetoothSecureChannel(mode: .certificate(try credential(.bob)), direction: .inbound)

        let responderReply = try responder.receive(try initiator.start()).bytesToSend
        XCTAssertFalse(responder.isOpen, "the responder has not seen the initiator's certificate yet")

        let (handshakeReply, responderCertificate) = splitFirstMessage(responderReply)
        let initiatorCertificate = try initiator.receive(handshakeReply).bytesToSend
        XCTAssertFalse(initiator.isOpen, "the initiator has not seen the responder's certificate yet")
        XCTAssertThrowsError(try initiator.seal(Data("too early".utf8)))

        XCTAssertTrue(try initiator.receive(responderCertificate).plaintext.isEmpty)
        XCTAssertTrue(initiator.isOpen)
        XCTAssertEqual(try data(initiator.peerCertificateChain), try PeerNetworkCertificateFixtures.certificateData(.bob))

        _ = try responder.receive(initiatorCertificate)
        XCTAssertTrue(responder.isOpen)
        XCTAssertEqual(try data(responder.peerCertificateChain), try PeerNetworkCertificateFixtures.certificateData(.alice))

        let message = Data("authenticated".utf8)
        XCTAssertEqual(try responder.receive(try initiator.seal(message)).plaintext, message)
        XCTAssertEqual(try initiator.receive(try responder.seal(message)).plaintext, message)
    }

    func testInitiatorPresentingACertificateWithoutItsKeyIsRejected() throws {
        let impostor = BluetoothCertificateCredential(certificate: try certificate(.alice), privateKey: try privateKey(.mallory))
        let initiator = BluetoothSecureChannel(mode: .certificate(impostor), direction: .outbound)
        let responder = BluetoothSecureChannel(mode: .certificate(try credential(.bob)), direction: .inbound)

        let responderReply = try responder.receive(try initiator.start()).bytesToSend
        let initiatorCertificate = try initiator.receive(responderReply).bytesToSend
        XCTAssertThrowsError(try responder.receive(initiatorCertificate))
        XCTAssertFalse(responder.isOpen)
        XCTAssertNil(responder.peerCertificateChain)
    }

    func testResponderPresentingACertificateWithoutItsKeyIsRejected() throws {
        let impostor = BluetoothCertificateCredential(certificate: try certificate(.bob), privateKey: try privateKey(.mallory))
        let initiator = BluetoothSecureChannel(mode: .certificate(try credential(.alice)), direction: .outbound)
        let responder = BluetoothSecureChannel(mode: .certificate(impostor), direction: .inbound)

        let responderReply = try responder.receive(try initiator.start()).bytesToSend
        XCTAssertThrowsError(try initiator.receive(responderReply))
        XCTAssertFalse(initiator.isOpen)
        XCTAssertNil(initiator.peerCertificateChain)
    }

    func testCertificateSignatureIsBoundToHandshakeRoleAndCertificate() throws {
        let alice = try credential(.alice)
        let handshakeHash = Data(repeating: 0xA1, count: 32)
        let message = try alice.certificateMessage(isInitiator: true, handshakeHash: handshakeHash)

        XCTAssertNoThrow(try BluetoothCertificateCredential.verifiedCertificate(in: message,
            signedByInitiator: true, handshakeHash: handshakeHash))
        XCTAssertThrowsError(try BluetoothCertificateCredential.verifiedCertificate(in: message,
            signedByInitiator: true, handshakeHash: Data(repeating: 0xB2, count: 32)), "another session's handshake")
        XCTAssertThrowsError(try BluetoothCertificateCredential.verifiedCertificate(in: message,
            signedByInitiator: false, handshakeHash: handshakeHash), "reflected back as the other role")

        // Alice's signature with Bob's certificate swapped in front of it.
        let aliceLength = message.prefix(4).reduce(0) { $0 << 8 | Int($1) }
        let signature = message.dropFirst(4 + aliceLength)
        let bobCertificate = try PeerNetworkCertificateFixtures.certificateData(.bob)
        var swapped = Data()
        withUnsafeBytes(of: UInt32(bobCertificate.count).bigEndian) { swapped.append(contentsOf: $0) }
        swapped.append(bobCertificate)
        swapped.append(signature)
        XCTAssertThrowsError(try BluetoothCertificateCredential.verifiedCertificate(in: swapped,
            signedByInitiator: true, handshakeHash: handshakeHash), "certificate substituted")
    }

    // MARK: - Pre-shared key and plaintext modes

    func testPreSharedKeyChannelsSplitMessagesAtTheNoiseLimit() throws {
        let key = BluetoothSecureChannel.noisePreSharedKey(for: Data("group key".utf8))
        let initiator = BluetoothSecureChannel(mode: .preSharedKey(key), direction: .outbound)
        let responder = BluetoothSecureChannel(mode: .preSharedKey(key), direction: .inbound)
        _ = try initiator.receive(try responder.receive(try initiator.start()).bytesToSend)
        XCTAssertTrue(initiator.isOpen && responder.isOpen)

        let large = Data((0..<200_000).map { UInt8($0 % 253) })
        let sealed = try initiator.seal(large)
        XCTAssertEqual(sealed.count, large.count + 4 * (2 + BluetoothNoise.tagLength), "four messages")
        XCTAssertEqual(try responder.receive(sealed).plaintext, large)
    }

    func testNoisePreSharedKeyIsALabelledDerivationOfTheAppKey() {
        let appKey = Data(repeating: 7, count: 32)
        let derived = BluetoothSecureChannel.noisePreSharedKey(for: appKey)
        XCTAssertEqual(derived.count, 32)
        XCTAssertNotEqual(derived, appKey)
        XCTAssertEqual(derived, BluetoothSecureChannel.noisePreSharedKey(for: appKey))
        XCTAssertNotEqual(derived, BluetoothSecureChannel.noisePreSharedKey(for: Data(repeating: 8, count: 32)))
    }

    func testPlaintextModePassesBytesThroughUnchanged() throws {
        let channel = BluetoothSecureChannel(mode: .plaintext, direction: .outbound)
        let bytes = Data("plain".utf8)
        XCTAssertTrue(channel.isOpen)
        XCTAssertEqual(try channel.start(), Data())
        XCTAssertEqual(try channel.seal(bytes), bytes)
        XCTAssertEqual(try channel.receive(bytes).plaintext, bytes)
    }

    func testTamperedTruncatedOrEmptyTransportMessagesFailTheChannel() throws {
        let key = BluetoothSecureChannel.noisePreSharedKey(for: Data("group key".utf8))
        func openPair() throws -> (BluetoothSecureChannel, BluetoothSecureChannel) {
            let initiator = BluetoothSecureChannel(mode: .preSharedKey(key), direction: .outbound)
            let responder = BluetoothSecureChannel(mode: .preSharedKey(key), direction: .inbound)
            _ = try initiator.receive(try responder.receive(try initiator.start()).bytesToSend)
            return (initiator, responder)
        }

        let payload = Data("payload".utf8)

        var (initiator, responder) = try openPair()
        let sealed = try initiator.seal(payload)
        // A message still arriving is held, then delivered whole.
        XCTAssertTrue(try responder.receive(sealed.dropLast(1)).plaintext.isEmpty)
        XCTAssertEqual(try responder.receive(sealed.suffix(1)).plaintext, payload)

        (initiator, responder) = try openPair()
        var tampered = try initiator.seal(payload)
        tampered[tampered.endIndex - 1] ^= 0x01
        XCTAssertThrowsError(try responder.receive(tampered), "tampered tag")

        (initiator, responder) = try openPair()
        let whole = try initiator.seal(payload)
        let truncated = Data([0, UInt8(whole.count - 3)]) + whole.dropFirst(2).dropLast(1)
        XCTAssertThrowsError(try responder.receive(truncated), "truncated ciphertext")

        // `seal` never emits an empty message, so drive a raw Noise initiator to send one.
        var raw = try BluetoothNoise.Handshake(pattern: .nnpsk0, isInitiator: true,
            prologue: BluetoothSecureChannel.prologue, preSharedKey: key)
        responder = BluetoothSecureChannel(mode: .preSharedKey(key), direction: .inbound)
        let reply = try responder.receive(lengthPrefixed(try raw.writeMessage(payload: Data()))).bytesToSend
        XCTAssertTrue(try raw.readMessage(Data(reply.dropFirst(2))).isEmpty)
        var rawSend = raw.split().send
        XCTAssertEqual(try responder.receive(lengthPrefixed(try rawSend.encrypt(associatedData: Data(),
            plaintext: payload))).plaintext, payload, "a raw Noise peer interoperates with the channel")
        XCTAssertThrowsError(try responder.receive(lengthPrefixed(try rawSend.encrypt(associatedData: Data(),
            plaintext: Data()))), "empty transport message")
    }

    private func lengthPrefixed(_ message: Data) -> Data {
        return Data([UInt8(message.count >> 8), UInt8(message.count & 0xFF)]) + message
    }

    func testChannelStaysFailedAfterAnError() throws {
        let key = BluetoothSecureChannel.noisePreSharedKey(for: Data("group key".utf8))
        let responder = BluetoothSecureChannel(mode: .preSharedKey(key), direction: .inbound)
        XCTAssertThrowsError(try responder.receive(Data([0, 48]) + Data(count: 48)))
        let genuine = BluetoothSecureChannel(mode: .preSharedKey(key), direction: .outbound)
        XCTAssertThrowsError(try responder.receive(try genuine.start()), "a failed channel never recovers")
    }

    // MARK: - Helpers

    private func splitFirstMessage(_ bytes: Data) -> (Data, Data) {
        let length = Int(bytes[bytes.startIndex]) << 8 | Int(bytes[bytes.startIndex + 1])
        return (Data(bytes.prefix(2 + length)), Data(bytes.dropFirst(2 + length)))
    }

    private func credential(_ name: PeerNetworkCertificateFixtures.Name) throws -> BluetoothCertificateCredential {
        return try XCTUnwrap(BluetoothCertificateCredential(identity: try PeerNetworkCertificateFixtures.identity(name)))
    }

    private func certificate(_ name: PeerNetworkCertificateFixtures.Name) throws -> SecCertificate {
        return try XCTUnwrap(SecCertificateCreateWithData(nil, try PeerNetworkCertificateFixtures.certificateData(name) as CFData))
    }

    private func privateKey(_ name: PeerNetworkCertificateFixtures.Name) throws -> SecKey {
        var key : SecKey?
        XCTAssertEqual(SecIdentityCopyPrivateKey(try PeerNetworkCertificateFixtures.identity(name), &key), errSecSuccess)
        return try XCTUnwrap(key)
    }

    private func data(_ chain: [SecCertificate]?) throws -> Data {
        return SecCertificateCopyData(try XCTUnwrap(chain?.first)) as Data
    }
}
