//
//  BluetoothSecureChannel.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import CryptoKit
import Security
import PeerConnectivity

/// Gives a Bluetooth byte stream the protection an app chose with `PeerConnectionNetworkSecurity`,
/// so an app can swap backends without changing its security settings.
///
/// - `.unauthenticated`: bytes pass through unchanged, like plaintext TCP on the Network backend.
/// - `.preSharedKey`: `Noise_NNpsk0`, where both sides prove the key and gain forward secrecy.
/// - `.certificate`: `Noise_NN`, then each side sends its certificate and a signature over the
///   handshake, as TLS 1.3 CertificateVerify does. Trust stays with the app's certificate policy.
///
/// Nothing the app sends or receives passes through until the peer is authenticated. The channel
/// does no I/O: it turns received bytes into bytes to send and plaintext to deliver.
@available(iOS 13.0, macOS 10.15, *)
internal final class BluetoothSecureChannel {

    internal enum Mode {
        case plaintext
        /// A 32-byte Noise key; see `noisePreSharedKey(for:)`.
        case preSharedKey(Data)
        case certificate(BluetoothCertificateCredential)
    }

    internal struct Output {
        internal var bytesToSend = Data()
        internal var plaintext = Data()
    }

    internal enum ChannelError : Error {
        case unexpectedPayload
        case messageTooLarge
        case certificateRejected
        case notOpen
    }

    fileprivate struct Transport {
        var send : BluetoothNoise.CipherState
        var receive : BluetoothNoise.CipherState
        let handshakeHash : Data
    }

    fileprivate enum State {
        case plaintext
        case handshaking(BluetoothNoise.Handshake)
        case awaitingPeerCertificate(Transport)
        case open(Transport)
        case failed
    }

    /// Bound into every handshake, so a different protocol or version cannot complete one.
    internal static let prologue = Data("PeerConnectivity.Bluetooth.v1".utf8)
    internal static let maxPlaintextPerMessage = BluetoothNoise.maxMessageLength - BluetoothNoise.tagLength
    fileprivate static let lengthPrefixLength = 2

    fileprivate var state : State
    fileprivate let credential : BluetoothCertificateCredential?
    fileprivate let isInitiator : Bool
    fileprivate var incoming = Data()
    /// Bytes of `incoming` already consumed; compacted once per `receive` so parsing stays linear.
    fileprivate var incomingOffset = 0

    /// The peer's verified leaf certificate, once its signature has been checked. Leaf only, as on
    /// the Network backend, where `sec_identity_create` presents only the identity's certificate.
    internal fileprivate(set) var peerCertificateChain : [SecCertificate]?

    internal var isOpen : Bool {
        switch state {
        case .plaintext, .open: return true
        default: return false
        }
    }

    internal convenience init(security: PeerConnectionNetworkSecurity, direction: NetworkPeerConnectionDirection) {
        switch security {
        case .unauthenticated:
            self.init(mode: .plaintext, direction: direction)
        case .preSharedKey(let key):
            precondition(!key.isEmpty, "PeerConnectivity: Bluetooth pre-shared key must not be empty")
            self.init(mode: .preSharedKey(BluetoothSecureChannel.noisePreSharedKey(for: key)), direction: direction)
        case .certificate(let identity):
            guard let credential = BluetoothCertificateCredential(identity: identity) else {
                preconditionFailure("PeerConnectivity: Bluetooth certificate identity is invalid or uses an unsupported key type")
            }
            self.init(mode: .certificate(credential), direction: direction)
        }
    }

    internal init(mode: Mode, direction: NetworkPeerConnectionDirection) {
        isInitiator = direction == .outbound
        switch mode {
        case .plaintext:
            credential = nil
            state = .plaintext
        case .preSharedKey(let key):
            credential = nil
            state = BluetoothSecureChannel.handshakeState(pattern: .nnpsk0, isInitiator: isInitiator, preSharedKey: key)
        case .certificate(let credential):
            self.credential = credential
            state = BluetoothSecureChannel.handshakeState(pattern: .nn, isInitiator: isInitiator, preSharedKey: nil)
        }
    }

    /// The same app key also drives TLS-PSK on the Network backend; a labelled HMAC gives Noise
    /// a 32-byte key of its own instead of reusing those bytes directly.
    ///
    /// As with TLS-PSK, someone who records the first handshake message can test guesses at the
    /// key offline, so the app key must be random (the demo uses 32 random bytes), not a passphrase.
    internal static func noisePreSharedKey(for key: Data) -> Data {
        return Data(HMAC<SHA256>.authenticationCode(for: key,
            using: SymmetricKey(data: Data("PeerConnectivity.Bluetooth.PSK.v1".utf8))))
    }

    /// Bytes to send as soon as the link opens: the first handshake message for the initiator.
    internal func start() throws -> Data {
        guard case .handshaking(var handshake) = state, isInitiator else { return Data() }
        do {
            let message = try handshake.writeMessage(payload: Data())
            state = .handshaking(handshake)
            return try BluetoothSecureChannel.lengthPrefixed(message)
        } catch {
            state = .failed
            throw error
        }
    }

    internal func receive(_ bytes: Data) throws -> Output {
        if case .plaintext = state {
            return Output(bytesToSend: Data(), plaintext: bytes)
        }
        var output = Output()
        incoming.append(bytes)
        do {
            while let message = nextMessage() {
                try handle(message, output: &output)
            }
            if incomingOffset > 0 {
                incoming = Data(incoming.dropFirst(incomingOffset))
                incomingOffset = 0
            }
            return output
        } catch {
            state = .failed
            throw error
        }
    }

    /// Splits plaintext into Noise transport messages. Only valid once the channel is open.
    internal func seal(_ plaintext: Data) throws -> Data {
        switch state {
        case .plaintext:
            return plaintext
        case .open(var transport):
            var sealed = Data()
            var offset = plaintext.startIndex
            while offset < plaintext.endIndex {
                let end = plaintext.index(offset, offsetBy: BluetoothSecureChannel.maxPlaintextPerMessage,
                    limitedBy: plaintext.endIndex) ?? plaintext.endIndex
                let message = try transport.send.encrypt(associatedData: Data(), plaintext: Data(plaintext[offset..<end]))
                sealed.append(try BluetoothSecureChannel.lengthPrefixed(message))
                offset = end
            }
            state = .open(transport)
            return sealed
        default:
            throw ChannelError.notOpen
        }
    }

    // MARK: - Message handling

    fileprivate func handle(_ message: Data, output: inout Output) throws {
        switch state {
        case .handshaking(var handshake):
            // Handshake payloads are unused; anything there is a different or tampered protocol.
            guard try handshake.readMessage(message).isEmpty else { throw ChannelError.unexpectedPayload }
            if !handshake.isComplete {
                output.bytesToSend.append(try BluetoothSecureChannel.lengthPrefixed(handshake.writeMessage(payload: Data())))
            }
            let ciphers = handshake.split()
            var transport = Transport(send: ciphers.send, receive: ciphers.receive, handshakeHash: handshake.handshakeHash)
            guard let credential = credential else {
                state = .open(transport)
                return
            }
            let certificateMessage = try credential.certificateMessage(isInitiator: isInitiator,
                handshakeHash: transport.handshakeHash)
            let sealed = try transport.send.encrypt(associatedData: Data(), plaintext: certificateMessage)
            output.bytesToSend.append(try BluetoothSecureChannel.lengthPrefixed(sealed))
            state = .awaitingPeerCertificate(transport)

        case .awaitingPeerCertificate(var transport):
            let certificateMessage = try transport.receive.decrypt(associatedData: Data(), ciphertext: message)
            let certificate = try BluetoothCertificateCredential.verifiedCertificate(in: certificateMessage,
                signedByInitiator: !isInitiator,
                handshakeHash: transport.handshakeHash)
            peerCertificateChain = [certificate]
            state = .open(transport)

        case .open(var transport):
            let plaintext = try transport.receive.decrypt(associatedData: Data(), ciphertext: message)
            // `seal` never sends an empty message; accepting them would let a peer buy one AEAD
            // operation per 18 bytes without ever moving data.
            guard !plaintext.isEmpty else { throw ChannelError.unexpectedPayload }
            output.plaintext.append(plaintext)
            state = .open(transport)

        case .plaintext, .failed:
            throw ChannelError.notOpen
        }
    }

    /// The next whole length-prefixed message, or nil until more bytes arrive.
    fileprivate func nextMessage() -> Data? {
        let start = incoming.startIndex + incomingOffset
        guard incoming.endIndex - start >= BluetoothSecureChannel.lengthPrefixLength else { return nil }
        let length = Int(incoming[start]) << 8 | Int(incoming[start + 1])
        let end = start + BluetoothSecureChannel.lengthPrefixLength + length
        guard incoming.endIndex >= end else { return nil }
        incomingOffset += BluetoothSecureChannel.lengthPrefixLength + length
        return Data(incoming[(start + BluetoothSecureChannel.lengthPrefixLength)..<end])
    }

    fileprivate static func lengthPrefixed(_ message: Data) throws -> Data {
        guard message.count <= BluetoothNoise.maxMessageLength else { throw ChannelError.messageTooLarge }
        return Data([UInt8(message.count >> 8), UInt8(message.count & 0xFF)]) + message
    }

    fileprivate static func handshakeState(pattern: BluetoothNoise.Pattern, isInitiator: Bool, preSharedKey: Data?) -> State {
        do {
            return .handshaking(try BluetoothNoise.Handshake(pattern: pattern, isInitiator: isInitiator,
                prologue: prologue, preSharedKey: preSharedKey))
        } catch {
            preconditionFailure("PeerConnectivity: Bluetooth Noise key must be 32 bytes")
        }
    }
}

/// The local certificate and the private key that proves possession of it.
@available(iOS 13.0, macOS 10.15, *)
internal struct BluetoothCertificateCredential {

    internal let certificate : SecCertificate
    internal let privateKey : SecKey

    internal init?(identity: SecIdentity) {
        var certificate : SecCertificate?
        var privateKey : SecKey?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
            SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess,
            let certificate = certificate,
            let privateKey = privateKey,
            let algorithm = BluetoothCertificateCredential.signatureAlgorithm(for: certificate),
            SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            return nil
        }
        self.init(certificate: certificate, privateKey: privateKey)
    }

    /// Pairs any certificate with any key; tests use it to model a peer presenting a stolen certificate.
    internal init(certificate: SecCertificate, privateKey: SecKey) {
        self.certificate = certificate
        self.privateKey = privateKey
    }

    /// Certificate length (4 bytes, big-endian), certificate DER, then the signature.
    internal func certificateMessage(isInitiator: Bool, handshakeHash: Data) throws -> Data {
        let der = SecCertificateCopyData(certificate) as Data
        guard let algorithm = BluetoothCertificateCredential.signatureAlgorithm(for: certificate) else {
            throw BluetoothSecureChannel.ChannelError.certificateRejected
        }
        let signedContent = BluetoothCertificateCredential.signedContent(signedByInitiator: isInitiator,
            handshakeHash: handshakeHash, certificateData: der)
        var error : Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, algorithm, signedContent as CFData, &error) as Data? else {
            throw error?.takeRetainedValue() ?? BluetoothSecureChannel.ChannelError.certificateRejected
        }
        var message = Data()
        withUnsafeBytes(of: UInt32(der.count).bigEndian) { message.append(contentsOf: $0) }
        message.append(der)
        message.append(signature)
        return message
    }

    /// Checks that the sender holds the key for the certificate it presents, for this handshake and role.
    /// Whether the certificate is trusted is left to the app's certificate policy.
    internal static func verifiedCertificate(in message: Data, signedByInitiator: Bool, handshakeHash: Data) throws -> SecCertificate {
        let message = Data(message)
        guard message.count > 4 else { throw BluetoothSecureChannel.ChannelError.certificateRejected }
        let length = message.prefix(4).reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, message.count > 4 + length else { throw BluetoothSecureChannel.ChannelError.certificateRejected }
        let der = message.subdata(in: 4..<(4 + length))
        let signature = message.subdata(in: (4 + length)..<message.count)
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData),
            let publicKey = SecCertificateCopyKey(certificate),
            let algorithm = signatureAlgorithm(for: certificate) else {
            throw BluetoothSecureChannel.ChannelError.certificateRejected
        }
        let signedContent = self.signedContent(signedByInitiator: signedByInitiator,
            handshakeHash: handshakeHash, certificateData: der)
        guard SecKeyVerifySignature(publicKey, algorithm, signedContent as CFData, signature as CFData, nil) else {
            throw BluetoothSecureChannel.ChannelError.certificateRejected
        }
        return certificate
    }

    /// A role label stops a signature being reflected back; the handshake hash ties it to this
    /// session's key exchange; the certificate digest stops a different certificate being swapped in.
    fileprivate static func signedContent(signedByInitiator: Bool, handshakeHash: Data, certificateData: Data) -> Data {
        let role = signedByInitiator ? "initiator" : "responder"
        return Data("PeerConnectivity.Bluetooth.v1.CertificateVerify.\(role)".utf8)
            + handshakeHash
            + Data(SHA256.hash(data: certificateData))
    }

    /// The algorithm follows from the certificate's key, so it is never negotiated on the wire.
    fileprivate static func signatureAlgorithm(for certificate: SecCertificate) -> SecKeyAlgorithm? {
        guard let key = SecCertificateCopyKey(certificate),
            let attributes = SecKeyCopyAttributes(key) as? [String:Any],
            let type = attributes[kSecAttrKeyType as String] as? String else {
            return nil
        }
        let algorithm : SecKeyAlgorithm
        if type == kSecAttrKeyTypeECSECPrimeRandom as String {
            algorithm = .ecdsaSignatureMessageX962SHA256
        } else if type == kSecAttrKeyTypeRSA as String {
            algorithm = .rsaSignatureMessagePSSSHA256
        } else {
            return nil
        }
        return SecKeyIsAlgorithmSupported(key, .verify, algorithm) ? algorithm : nil
    }
}
