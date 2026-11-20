//
//  BluetoothNoise.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import CryptoKit

/// The subset of the Noise Protocol Framework (revision 34) the Bluetooth backend needs:
/// the `NN` and `NNpsk0` patterns with X25519, ChaCha20-Poly1305 and SHA-256.
///
/// Names follow the specification so the code can be read against it section by section.
/// Behaviour is pinned by the published cacophony test vectors in `BluetoothNoiseTests`.
internal enum BluetoothNoise {

    internal enum Pattern {
        /// `-> e`, `<- e, ee`: ephemeral key agreement with no authentication of its own.
        case nn
        /// `-> psk, e`, `<- e, ee`: both sides prove the pre-shared key.
        case nnpsk0

        internal var protocolName : String {
            switch self {
            case .nn: return "Noise_NN_25519_ChaChaPoly_SHA256"
            case .nnpsk0: return "Noise_NNpsk0_25519_ChaChaPoly_SHA256"
            }
        }
    }

    internal enum NoiseError : Error {
        case invalidPreSharedKey
        case unexpectedMessage
        case truncatedMessage
        case invalidPublicKey
        case weakKeyAgreement
        case decryptionFailed
        case nonceExhausted
    }

    internal static let keyLength = 32
    internal static let tagLength = 16
    /// Every Noise message, handshake or transport, is at most 65535 bytes.
    internal static let maxMessageLength = 65535

    // MARK: - CipherState (spec section 5.1)

    internal struct CipherState {
        fileprivate var key : SymmetricKey?
        fileprivate var nonce : UInt64 = 0

        internal init(key: SymmetricKey? = nil) {
            self.key = key
        }

        internal mutating func encrypt(associatedData: Data, plaintext: Data) throws -> Data {
            guard let key = key else { return plaintext }
            // 2^64-1 is reserved by the specification.
            guard nonce < UInt64.max else { throw NoiseError.nonceExhausted }
            let box = try ChaChaPoly.seal(plaintext, using: key, nonce: try Self.chachaNonce(nonce),
                authenticating: associatedData)
            nonce += 1
            return box.ciphertext + box.tag
        }

        internal mutating func decrypt(associatedData: Data, ciphertext: Data) throws -> Data {
            guard let key = key else { return ciphertext }
            guard nonce < UInt64.max else { throw NoiseError.nonceExhausted }
            guard ciphertext.count >= tagLength else { throw NoiseError.truncatedMessage }
            do {
                let box = try ChaChaPoly.SealedBox(nonce: try Self.chachaNonce(nonce),
                    ciphertext: ciphertext.dropLast(tagLength),
                    tag: ciphertext.suffix(tagLength))
                let plaintext = try ChaChaPoly.open(box, using: key, authenticating: associatedData)
                // The nonce only advances on success, so a forged message cannot desynchronise it.
                nonce += 1
                return plaintext
            } catch {
                throw NoiseError.decryptionFailed
            }
        }

        /// 32 bits of zeros followed by the 64-bit little-endian counter.
        fileprivate static func chachaNonce(_ counter: UInt64) throws -> ChaChaPoly.Nonce {
            var bytes = Data(count: 4)
            withUnsafeBytes(of: counter.littleEndian) { bytes.append(contentsOf: $0) }
            return try ChaChaPoly.Nonce(data: bytes)
        }
    }

    // MARK: - SymmetricState (spec section 5.2)

    internal struct SymmetricState {
        fileprivate var cipher = CipherState()
        fileprivate var chainingKey : Data
        fileprivate(set) var handshakeHash : Data

        internal init(protocolName: String) {
            let name = Data(protocolName.utf8)
            handshakeHash = name.count <= keyLength
                ? name + Data(count: keyLength - name.count)
                : Data(SHA256.hash(data: name))
            chainingKey = handshakeHash
        }

        internal mutating func mixHash(_ data: Data) {
            handshakeHash = Data(SHA256.hash(data: handshakeHash + data))
        }

        internal mutating func mixKey(_ inputKeyMaterial: Data) {
            let output = BluetoothNoise.hkdf(chainingKey: chainingKey, inputKeyMaterial: inputKeyMaterial, outputs: 2)
            chainingKey = output[0]
            cipher = CipherState(key: SymmetricKey(data: output[1]))
        }

        internal mutating func mixKeyAndHash(_ inputKeyMaterial: Data) {
            let output = BluetoothNoise.hkdf(chainingKey: chainingKey, inputKeyMaterial: inputKeyMaterial, outputs: 3)
            chainingKey = output[0]
            mixHash(output[1])
            cipher = CipherState(key: SymmetricKey(data: output[2]))
        }

        internal mutating func encryptAndHash(_ plaintext: Data) throws -> Data {
            let ciphertext = try cipher.encrypt(associatedData: handshakeHash, plaintext: plaintext)
            mixHash(ciphertext)
            return ciphertext
        }

        internal mutating func decryptAndHash(_ ciphertext: Data) throws -> Data {
            let plaintext = try cipher.decrypt(associatedData: handshakeHash, ciphertext: ciphertext)
            mixHash(ciphertext)
            return plaintext
        }

        /// The initiator-to-responder cipher first, then responder-to-initiator.
        internal func split() -> (CipherState, CipherState) {
            let output = BluetoothNoise.hkdf(chainingKey: chainingKey, inputKeyMaterial: Data(), outputs: 2)
            return (CipherState(key: SymmetricKey(data: output[0])), CipherState(key: SymmetricKey(data: output[1])))
        }
    }

    /// HKDF as the specification defines it, built from HMAC-SHA256 because CryptoKit's `HKDF`
    /// needs iOS 14 and the package supports iOS 13.
    internal static func hkdf(chainingKey: Data, inputKeyMaterial: Data, outputs: Int) -> [Data] {
        let temporaryKey = SymmetricKey(data: HMAC<SHA256>.authenticationCode(for: inputKeyMaterial,
            using: SymmetricKey(data: chainingKey)))
        var previous = Data()
        return (1...outputs).map { index in
            previous = Data(HMAC<SHA256>.authenticationCode(for: previous + [UInt8(index)], using: temporaryKey))
            return previous
        }
    }

    // MARK: - HandshakeState (spec section 5.3), two-message patterns only

    internal struct Handshake {
        internal let isInitiator : Bool
        fileprivate let pattern : Pattern
        fileprivate let preSharedKey : Data?
        fileprivate let ephemeral : Curve25519.KeyAgreement.PrivateKey
        fileprivate var remoteEphemeral : Curve25519.KeyAgreement.PublicKey?
        fileprivate var symmetric : SymmetricState
        fileprivate var messageIndex = 0

        internal var isComplete : Bool { return messageIndex == 2 }
        internal var handshakeHash : Data { return symmetric.handshakeHash }

        /// - parameter ephemeral: Injected only by tests that replay published vectors.
        internal init(pattern: Pattern,
            isInitiator: Bool,
            prologue: Data,
            preSharedKey: Data? = nil,
            ephemeral: Curve25519.KeyAgreement.PrivateKey = Curve25519.KeyAgreement.PrivateKey()) throws {
            switch pattern {
            case .nn:
                guard preSharedKey == nil else { throw NoiseError.invalidPreSharedKey }
            case .nnpsk0:
                guard preSharedKey?.count == keyLength else { throw NoiseError.invalidPreSharedKey }
            }
            self.isInitiator = isInitiator
            self.pattern = pattern
            self.preSharedKey = preSharedKey
            self.ephemeral = ephemeral
            self.symmetric = SymmetricState(protocolName: pattern.protocolName)
            symmetric.mixHash(prologue)
        }

        internal mutating func writeMessage(payload: Data) throws -> Data {
            guard !isComplete, isInitiator == (messageIndex == 0) else { throw NoiseError.unexpectedMessage }
            var message = Data()
            if messageIndex == 0, let preSharedKey = preSharedKey {
                symmetric.mixKeyAndHash(preSharedKey)
            }
            let publicKey = ephemeral.publicKey.rawRepresentation
            message.append(publicKey)
            mixEphemeral(publicKey)
            if messageIndex == 1 {
                try mixEphemeralAgreement()
            }
            message.append(try symmetric.encryptAndHash(payload))
            messageIndex += 1
            return message
        }

        internal mutating func readMessage(_ message: Data) throws -> Data {
            guard !isComplete, isInitiator == (messageIndex == 1) else { throw NoiseError.unexpectedMessage }
            guard message.count >= keyLength else { throw NoiseError.truncatedMessage }
            if messageIndex == 0, let preSharedKey = preSharedKey {
                symmetric.mixKeyAndHash(preSharedKey)
            }
            let publicKey = Data(message.prefix(keyLength))
            do {
                remoteEphemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
            } catch {
                throw NoiseError.invalidPublicKey
            }
            mixEphemeral(publicKey)
            if messageIndex == 1 {
                try mixEphemeralAgreement()
            }
            let payload = try symmetric.decryptAndHash(Data(message.dropFirst(keyLength)))
            messageIndex += 1
            return payload
        }

        /// Ciphers for this side's sending and receiving directions.
        internal func split() -> (send: CipherState, receive: CipherState) {
            let (initiatorToResponder, responderToInitiator) = symmetric.split()
            return isInitiator
                ? (initiatorToResponder, responderToInitiator)
                : (responderToInitiator, initiatorToResponder)
        }

        /// The `e` token. PSK patterns also mix the key, so later payloads are encrypted (section 9.2).
        fileprivate mutating func mixEphemeral(_ publicKey: Data) {
            symmetric.mixHash(publicKey)
            if preSharedKey != nil {
                symmetric.mixKey(publicKey)
            }
        }

        /// The `ee` token.
        fileprivate mutating func mixEphemeralAgreement() throws {
            guard let remoteEphemeral = remoteEphemeral else { throw NoiseError.unexpectedMessage }
            let secret = try ephemeral.sharedSecretFromKeyAgreement(with: remoteEphemeral)
            let bytes = secret.withUnsafeBytes { Data($0) }
            // A low-order remote point yields all zeros; refuse it rather than derive guessable keys.
            guard bytes.contains(where: { $0 != 0 }) else { throw NoiseError.weakKeyAgreement }
            symmetric.mixKey(bytes)
        }
    }
}
