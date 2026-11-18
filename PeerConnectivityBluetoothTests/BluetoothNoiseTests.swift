//
//  BluetoothNoiseTests.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
import CryptoKit
@testable import PeerConnectivityBluetooth

/// Replays the cacophony test vectors (github.com/haskell-cryptography/cacophony, vectors/cacophony.txt),
/// which other Noise implementations also verify against, so a byte-for-byte match shows this
/// implementation follows the specification.
@available(iOS 13.0, macOS 10.15, *)
final class BluetoothNoiseTests : XCTestCase {

    // MARK: - Published vectors

    func testNNMatchesCacophonyVector() throws {
        try replay(pattern: .nn,
            preSharedKey: nil,
            handshakeHash: "9223fec1b892ec9d0dc2fb3bbeb261f170d1ea679f9c44ccf34aa131b4f5d97e",
            ciphertexts: [
                "ca35def5ae56cec33dc2036731ab14896bc4c75dbb07a61f879f8e3afa4c79444c756477696720766f6e204d69736573",
                "95ebc60d2b1fa672c1f46a8aa265ef51bfe38e7ccb39ec5be34069f144808843a0ff96bdf86b579ef7dbf94e812a7470b903c20a85a87e3a1fe863264ae547",
                "eb1a3e3d80c1792b1bb9cb0e1382f8d8322bfb1ca7c4c8517bb686",
                "c781b198d2a974eb1da2c7d518c000cf6396de87ca540963c03713",
            ])
    }

    func testNNpsk0MatchesCacophonyVector() throws {
        try replay(pattern: .nnpsk0,
            preSharedKey: "54686973206973206d7920417573747269616e20706572737065637469766521",
            handshakeHash: "f4d03dc34495c95729ea6de9e1b59004b59733102488b3e24bc441e0be208eaf",
            ciphertexts: [
                "ca35def5ae56cec33dc2036731ab14896bc4c75dbb07a61f879f8e3afa4c794479b962b8aff8485742ac32f905ba45369e2465fb59e138a93d67a0d1266b6a54",
                "95ebc60d2b1fa672c1f46a8aa265ef51bfe38e7ccb39ec5be34069f144808843d6062704d5a9c422a8e834423f8c1feada7e8d0d910a1a2cd030fb584221e3",
                "e632c3763d7669067383433197a3baddf146e9e70ad4b4e9e59e0f",
                "64c6bee32ea91c8474bb4c21d7a700109ad45af77b29764ba5eb1e",
            ])
    }

    // MARK: - Failure behaviour

    func testMismatchedPreSharedKeyFailsAtFirstMessage() throws {
        var initiator = try BluetoothNoise.Handshake(pattern: .nnpsk0, isInitiator: true, prologue: Data(),
            preSharedKey: Data(repeating: 1, count: 32))
        var responder = try BluetoothNoise.Handshake(pattern: .nnpsk0, isInitiator: false, prologue: Data(),
            preSharedKey: Data(repeating: 2, count: 32))
        let message = try initiator.writeMessage(payload: Data())
        XCTAssertThrowsError(try responder.readMessage(message))
    }

    func testDifferentProloguesFailAtSecondMessage() throws {
        var initiator = try BluetoothNoise.Handshake(pattern: .nn, isInitiator: true, prologue: Data("a".utf8))
        var responder = try BluetoothNoise.Handshake(pattern: .nn, isInitiator: false, prologue: Data("b".utf8))
        _ = try responder.readMessage(try initiator.writeMessage(payload: Data()))
        XCTAssertThrowsError(try initiator.readMessage(try responder.writeMessage(payload: Data())))
    }

    func testTamperedTransportMessageFailsAndKeepsTheNonce() throws {
        var (initiatorSend, responderReceive) = try completedNNTransport()
        let first = try initiatorSend.encrypt(associatedData: Data(), plaintext: Data("first".utf8))
        var tampered = first
        tampered[tampered.startIndex] ^= 0x01

        XCTAssertThrowsError(try responderReceive.decrypt(associatedData: Data(), ciphertext: tampered))
        XCTAssertEqual(try responderReceive.decrypt(associatedData: Data(), ciphertext: first), Data("first".utf8))
    }

    func testReplayedTransportMessageFails() throws {
        var (initiatorSend, responderReceive) = try completedNNTransport()
        let message = try initiatorSend.encrypt(associatedData: Data(), plaintext: Data("once".utf8))
        _ = try responderReceive.decrypt(associatedData: Data(), ciphertext: message)
        XCTAssertThrowsError(try responderReceive.decrypt(associatedData: Data(), ciphertext: message))
    }

    func testMessagesOutOfTurnAreRejected() throws {
        var initiator = try BluetoothNoise.Handshake(pattern: .nn, isInitiator: true, prologue: Data())
        var responder = try BluetoothNoise.Handshake(pattern: .nn, isInitiator: false, prologue: Data())
        XCTAssertThrowsError(try responder.writeMessage(payload: Data()))
        XCTAssertThrowsError(try initiator.readMessage(Data(count: 48)))
    }

    func testPreSharedKeyMustMatchThePattern() {
        XCTAssertThrowsError(try BluetoothNoise.Handshake(pattern: .nnpsk0, isInitiator: true, prologue: Data(),
            preSharedKey: Data(count: 31)))
        XCTAssertThrowsError(try BluetoothNoise.Handshake(pattern: .nn, isInitiator: true, prologue: Data(),
            preSharedKey: Data(count: 32)))
    }

    // MARK: - Helpers

    /// Runs both sides of a vector: two handshake messages, then one transport message each way.
    private func replay(pattern: BluetoothNoise.Pattern,
        preSharedKey: String?,
        handshakeHash: String,
        ciphertexts: [String]) throws {
        let prologue = hex("4a6f686e2047616c74")
        let payloads = [
            hex("4c756477696720766f6e204d69736573"),
            hex("4d757272617920526f746862617264"),
            hex("462e20412e20486179656b"),
            hex("4361726c204d656e676572"),
        ]
        var initiator = try BluetoothNoise.Handshake(pattern: pattern, isInitiator: true, prologue: prologue,
            preSharedKey: preSharedKey.map(hex),
            ephemeral: try .init(rawRepresentation: hex("893e28b9dc6ca8d611ab664754b8ceb7bac5117349a4439a6b0569da977c464a")))
        var responder = try BluetoothNoise.Handshake(pattern: pattern, isInitiator: false, prologue: prologue,
            preSharedKey: preSharedKey.map(hex),
            ephemeral: try .init(rawRepresentation: hex("bbdb4cdbd309f1a1f2e1456967fe288cadd6f712d65dc7b7793d5e63da6b375b")))

        let first = try initiator.writeMessage(payload: payloads[0])
        XCTAssertEqual(first, hex(ciphertexts[0]))
        XCTAssertEqual(try responder.readMessage(first), payloads[0])

        let second = try responder.writeMessage(payload: payloads[1])
        XCTAssertEqual(second, hex(ciphertexts[1]))
        XCTAssertEqual(try initiator.readMessage(second), payloads[1])

        XCTAssertTrue(initiator.isComplete && responder.isComplete)
        XCTAssertEqual(initiator.handshakeHash, hex(handshakeHash))
        XCTAssertEqual(responder.handshakeHash, hex(handshakeHash))

        var (initiatorSend, initiatorReceive) = initiator.split()
        var (responderSend, responderReceive) = responder.split()

        let third = try initiatorSend.encrypt(associatedData: Data(), plaintext: payloads[2])
        XCTAssertEqual(third, hex(ciphertexts[2]))
        XCTAssertEqual(try responderReceive.decrypt(associatedData: Data(), ciphertext: third), payloads[2])

        let fourth = try responderSend.encrypt(associatedData: Data(), plaintext: payloads[3])
        XCTAssertEqual(fourth, hex(ciphertexts[3]))
        XCTAssertEqual(try initiatorReceive.decrypt(associatedData: Data(), ciphertext: fourth), payloads[3])
    }

    private func completedNNTransport() throws -> (BluetoothNoise.CipherState, BluetoothNoise.CipherState) {
        var initiator = try BluetoothNoise.Handshake(pattern: .nn, isInitiator: true, prologue: Data())
        var responder = try BluetoothNoise.Handshake(pattern: .nn, isInitiator: false, prologue: Data())
        _ = try responder.readMessage(try initiator.writeMessage(payload: Data()))
        _ = try initiator.readMessage(try responder.writeMessage(payload: Data()))
        return (initiator.split().send, responder.split().receive)
    }

    private func hex(_ string: String) -> Data {
        var data = Data()
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            data.append(UInt8(string[index..<next], radix: 16)!)
            index = next
        }
        return data
    }
}
