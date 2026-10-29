//
//  PeerNetworkAuthentication.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 9/29/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import CryptoKit
import Security

internal enum PeerNetworkAuthenticationRole : UInt8 {
    case initiator = 1
    case responder = 2
}

internal enum PeerNetworkAuthenticationAlgorithm : UInt8 {
    case curve25519Signing = 1
}

internal enum PeerNetworkAuthenticationError : Error, Equatable {
    case invalidNonce
    case randomFailure(OSStatus)
    case invalidAuthenticationVersion
    case invalidProtocolVersion
    case invalidRole
    case invalidAlgorithm
    case invalidService
    case invalidIdentifier
    case invalidDisplayName
    case invalidPublicKey
    case invalidKeyIdentifier
    case invalidSignature
    case mismatchedContext
    case duplicateNonce
    case signerMismatch
    case malformedEncoding
    case oversizedEncoding
}

internal struct PeerNetworkAuthenticationNonce : Equatable {

    internal static let byteCount = 32
    internal typealias FillRandomBytes = (UnsafeMutableRawBufferPointer) -> OSStatus

    internal let data : Data

    internal init(data: Data) throws {
        guard data.count == PeerNetworkAuthenticationNonce.byteCount else {
            throw PeerNetworkAuthenticationError.invalidNonce
        }
        self.data = data
    }

    /// Call once for every connection attempt and role. A higher layer must reject nonce reuse and accept a transcript once.
    internal static func generate(
        fillRandomBytes: FillRandomBytes = { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }) throws -> PeerNetworkAuthenticationNonce {
        var data = Data(count: byteCount)
        let status = data.withUnsafeMutableBytes(fillRandomBytes)
        guard status == errSecSuccess else { throw PeerNetworkAuthenticationError.randomFailure(status) }
        return try PeerNetworkAuthenticationNonce(data: data)
    }
}

internal struct PeerNetworkAuthenticationHello : Equatable {

    internal static let currentAuthenticationVersion : UInt8 = 1
    internal static let authenticatedProtocolVersion : UInt16 = 2
    internal static let maxServiceByteLength = 15
    internal static let maxEncodedByteLength = 1024

    internal let authenticationVersion : UInt8
    internal let protocolVersion : UInt16
    internal let role : PeerNetworkAuthenticationRole
    internal let algorithm : PeerNetworkAuthenticationAlgorithm
    internal let service : String
    internal let nonce : PeerNetworkAuthenticationNonce
    internal let identity : PeerIdentity
    internal let publicKey : Data
    internal let keyIdentifier : Data

    internal init(
        protocolVersion: UInt16,
        role: PeerNetworkAuthenticationRole,
        service: String,
        nonce: PeerNetworkAuthenticationNonce,
        identity: PeerIdentity,
        publicKey: Data,
        keyIdentifier: Data? = nil,
        algorithm: PeerNetworkAuthenticationAlgorithm = .curve25519Signing,
        authenticationVersion: UInt8 = PeerNetworkAuthenticationHello.currentAuthenticationVersion
    ) throws {
        guard authenticationVersion == PeerNetworkAuthenticationHello.currentAuthenticationVersion else {
            throw PeerNetworkAuthenticationError.invalidAuthenticationVersion
        }
        guard protocolVersion == PeerNetworkAuthenticationHello.authenticatedProtocolVersion else {
            throw PeerNetworkAuthenticationError.invalidProtocolVersion
        }
        guard PeerConnectionManager.isValidServiceType(service),
            service.utf8.count <= PeerNetworkAuthenticationHello.maxServiceByteLength else {
            throw PeerNetworkAuthenticationError.invalidService
        }
        guard PeerIdentity.isValidIdentifier(identity.identifier) else {
            throw PeerNetworkAuthenticationError.invalidIdentifier
        }
        guard Peer.isValidDisplayName(identity.displayName) else {
            throw PeerNetworkAuthenticationError.invalidDisplayName
        }
        guard publicKey.count == PeerPersistentSigningIdentity.publicKeyByteCount else {
            throw PeerNetworkAuthenticationError.invalidPublicKey
        }
        let expectedKeyIdentifier = PeerPersistentSigningIdentity.keyIdentifier(for: publicKey)
        let suppliedKeyIdentifier = keyIdentifier ?? expectedKeyIdentifier
        guard suppliedKeyIdentifier.count == PeerPersistentSigningIdentity.keyIdentifierByteCount,
            suppliedKeyIdentifier == expectedKeyIdentifier else {
            throw PeerNetworkAuthenticationError.invalidKeyIdentifier
        }

        self.authenticationVersion = authenticationVersion
        self.protocolVersion = protocolVersion
        self.role = role
        self.algorithm = algorithm
        self.service = service
        self.nonce = nonce
        self.identity = identity
        self.publicKey = publicKey
        self.keyIdentifier = suppliedKeyIdentifier
    }

    internal func encoded() -> Data {
        var writer = PeerNetworkAuthenticationWriter()
        writer.append(PeerNetworkAuthenticationEncoding.helloDomain)
        writer.append(authenticationVersion)
        writer.append(protocolVersion)
        writer.append(role.rawValue)
        writer.append(algorithm.rawValue)
        writer.appendLengthPrefixed(service)
        writer.append(nonce.data)
        writer.appendLengthPrefixed(identity.identifier)
        writer.appendLengthPrefixed(identity.displayName)
        writer.append(publicKey)
        writer.append(keyIdentifier)
        return writer.data
    }

    internal static func decode(_ data: Data) throws -> PeerNetworkAuthenticationHello {
        guard data.count <= maxEncodedByteLength else { throw PeerNetworkAuthenticationError.oversizedEncoding }
        var reader = PeerNetworkAuthenticationReader(data: data)
        guard try reader.readData(count: PeerNetworkAuthenticationEncoding.helloDomain.count)
            == PeerNetworkAuthenticationEncoding.helloDomain else {
            throw PeerNetworkAuthenticationError.malformedEncoding
        }

        let authenticationVersion = try reader.readUInt8()
        guard authenticationVersion == currentAuthenticationVersion else {
            throw PeerNetworkAuthenticationError.invalidAuthenticationVersion
        }
        let protocolVersion = try reader.readUInt16()
        guard protocolVersion == authenticatedProtocolVersion else {
            throw PeerNetworkAuthenticationError.invalidProtocolVersion
        }
        guard let role = PeerNetworkAuthenticationRole(rawValue: try reader.readUInt8()) else {
            throw PeerNetworkAuthenticationError.invalidRole
        }
        guard let algorithm = PeerNetworkAuthenticationAlgorithm(rawValue: try reader.readUInt8()) else {
            throw PeerNetworkAuthenticationError.invalidAlgorithm
        }
        let service = try reader.readString(maxByteLength: maxServiceByteLength)
        let nonce = try PeerNetworkAuthenticationNonce(
            data: reader.readData(count: PeerNetworkAuthenticationNonce.byteCount))
        let identifier = try reader.readString(maxByteLength: PeerIdentity.maxIdentifierByteLength)
        let displayName = try reader.readString(maxByteLength: 63)
        let publicKey = try reader.readData(count: PeerPersistentSigningIdentity.publicKeyByteCount)
        let keyIdentifier = try reader.readData(count: PeerPersistentSigningIdentity.keyIdentifierByteCount)
        guard reader.isAtEnd else { throw PeerNetworkAuthenticationError.malformedEncoding }

        let hello = try PeerNetworkAuthenticationHello(
            protocolVersion: protocolVersion,
            role: role,
            service: service,
            nonce: nonce,
            identity: PeerIdentity(identifier: identifier, displayName: displayName),
            publicKey: publicKey,
            keyIdentifier: keyIdentifier,
            algorithm: algorithm,
            authenticationVersion: authenticationVersion)
        guard hello.encoded() == data else { throw PeerNetworkAuthenticationError.malformedEncoding }
        return hello
    }
}

internal struct PeerNetworkAuthenticationTranscript : Equatable {

    internal static let maxEncodedByteLength = 4096

    internal let initiator : PeerNetworkAuthenticationHello
    internal let responder : PeerNetworkAuthenticationHello

    internal init(
        _ first: PeerNetworkAuthenticationHello,
        _ second: PeerNetworkAuthenticationHello
    ) throws {
        let initiator : PeerNetworkAuthenticationHello
        let responder : PeerNetworkAuthenticationHello
        switch (first.role, second.role) {
        case (.initiator, .responder):
            initiator = first
            responder = second
        case (.responder, .initiator):
            initiator = second
            responder = first
        default:
            throw PeerNetworkAuthenticationError.invalidRole
        }

        guard initiator.authenticationVersion == responder.authenticationVersion,
            initiator.protocolVersion == responder.protocolVersion,
            initiator.algorithm == responder.algorithm,
            Data(initiator.service.utf8) == Data(responder.service.utf8) else {
            throw PeerNetworkAuthenticationError.mismatchedContext
        }
        guard initiator.nonce != responder.nonce else {
            throw PeerNetworkAuthenticationError.duplicateNonce
        }

        self.initiator = initiator
        self.responder = responder
    }

    internal func hello(for role: PeerNetworkAuthenticationRole) -> PeerNetworkAuthenticationHello {
        switch role {
        case .initiator:
            return initiator
        case .responder:
            return responder
        }
    }

    internal func encoded() -> Data {
        let initiatorData = initiator.encoded()
        let responderData = responder.encoded()
        var writer = PeerNetworkAuthenticationWriter()
        writer.append(PeerNetworkAuthenticationEncoding.transcriptDomain)
        writer.append(UInt32(initiatorData.count))
        writer.append(initiatorData)
        writer.append(UInt32(responderData.count))
        writer.append(responderData)
        return writer.data
    }

    internal static func decode(_ data: Data) throws -> PeerNetworkAuthenticationTranscript {
        guard data.count <= maxEncodedByteLength else { throw PeerNetworkAuthenticationError.oversizedEncoding }
        var reader = PeerNetworkAuthenticationReader(data: data)
        guard try reader.readData(count: PeerNetworkAuthenticationEncoding.transcriptDomain.count)
            == PeerNetworkAuthenticationEncoding.transcriptDomain else {
            throw PeerNetworkAuthenticationError.malformedEncoding
        }
        let initiatorLength = try reader.readBoundedLength(maximum: PeerNetworkAuthenticationHello.maxEncodedByteLength)
        let initiator = try PeerNetworkAuthenticationHello.decode(reader.readData(count: initiatorLength))
        let responderLength = try reader.readBoundedLength(maximum: PeerNetworkAuthenticationHello.maxEncodedByteLength)
        let responder = try PeerNetworkAuthenticationHello.decode(reader.readData(count: responderLength))
        guard reader.isAtEnd,
            initiator.role == .initiator,
            responder.role == .responder else {
            throw PeerNetworkAuthenticationError.malformedEncoding
        }
        let transcript = try PeerNetworkAuthenticationTranscript(initiator, responder)
        guard transcript.encoded() == data else { throw PeerNetworkAuthenticationError.malformedEncoding }
        return transcript
    }
}

internal struct PeerNetworkAuthenticationProof : Equatable {

    internal static let maxEncodedByteLength = 256

    internal let authenticationVersion : UInt8
    internal let algorithm : PeerNetworkAuthenticationAlgorithm
    internal let signerRole : PeerNetworkAuthenticationRole
    internal let keyIdentifier : Data
    internal let signature : Data

    internal static func sign(
        transcript: PeerNetworkAuthenticationTranscript,
        as signerRole: PeerNetworkAuthenticationRole,
        using signer: PeerIdentitySigning
    ) throws -> PeerNetworkAuthenticationProof {
        let hello = transcript.hello(for: signerRole)
        guard signer.publicKeyRepresentation == hello.publicKey,
            signer.keyIdentifier == hello.keyIdentifier else {
            throw PeerNetworkAuthenticationError.signerMismatch
        }
        let signature = try signer.signature(for: signedPayload(
            transcript: transcript,
            signerRole: signerRole,
            authenticationVersion: hello.authenticationVersion,
            algorithm: hello.algorithm,
            keyIdentifier: hello.keyIdentifier))
        return try PeerNetworkAuthenticationProof(
            authenticationVersion: hello.authenticationVersion,
            algorithm: hello.algorithm,
            signerRole: signerRole,
            keyIdentifier: hello.keyIdentifier,
            signature: signature)
    }

    internal init(
        authenticationVersion: UInt8,
        algorithm: PeerNetworkAuthenticationAlgorithm,
        signerRole: PeerNetworkAuthenticationRole,
        keyIdentifier: Data,
        signature: Data
    ) throws {
        guard authenticationVersion == PeerNetworkAuthenticationHello.currentAuthenticationVersion else {
            throw PeerNetworkAuthenticationError.invalidAuthenticationVersion
        }
        guard keyIdentifier.count == PeerPersistentSigningIdentity.keyIdentifierByteCount else {
            throw PeerNetworkAuthenticationError.invalidKeyIdentifier
        }
        guard signature.count == PeerPersistentSigningIdentity.signatureByteCount else {
            throw PeerNetworkAuthenticationError.invalidSignature
        }
        self.authenticationVersion = authenticationVersion
        self.algorithm = algorithm
        self.signerRole = signerRole
        self.keyIdentifier = keyIdentifier
        self.signature = signature
    }

    /// Verification requires the exact locally generated hello so a self-contained replay cannot choose its own context.
    internal func hasValidProofOfPossession(
        for transcript: PeerNetworkAuthenticationTranscript,
        expectedSignerRole: PeerNetworkAuthenticationRole,
        localHello: PeerNetworkAuthenticationHello
    ) -> Bool {
        guard signerRole == expectedSignerRole,
            localHello.role != expectedSignerRole,
            transcript.hello(for: localHello.role).encoded() == localHello.encoded() else { return false }
        let hello = transcript.hello(for: expectedSignerRole)
        guard authenticationVersion == hello.authenticationVersion,
            algorithm == hello.algorithm,
            keyIdentifier == hello.keyIdentifier else { return false }
        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: hello.publicKey)
            return publicKey.isValidSignature(
                signature,
                for: PeerNetworkAuthenticationProof.signedPayload(
                    transcript: transcript,
                    signerRole: signerRole,
                    authenticationVersion: authenticationVersion,
                    algorithm: algorithm,
                    keyIdentifier: keyIdentifier))
        } catch {
            return false
        }
    }

    private static func signedPayload(
        transcript: PeerNetworkAuthenticationTranscript,
        signerRole: PeerNetworkAuthenticationRole,
        authenticationVersion: UInt8,
        algorithm: PeerNetworkAuthenticationAlgorithm,
        keyIdentifier: Data
    ) -> Data {
        let transcriptData = transcript.encoded()
        var writer = PeerNetworkAuthenticationWriter()
        writer.append(PeerNetworkAuthenticationEncoding.signedProofDomain)
        writer.append(authenticationVersion)
        writer.append(algorithm.rawValue)
        writer.append(signerRole.rawValue)
        writer.append(keyIdentifier)
        writer.append(UInt32(transcriptData.count))
        writer.append(transcriptData)
        return writer.data
    }

    internal func encoded() -> Data {
        var writer = PeerNetworkAuthenticationWriter()
        writer.append(PeerNetworkAuthenticationEncoding.proofDomain)
        writer.append(authenticationVersion)
        writer.append(algorithm.rawValue)
        writer.append(signerRole.rawValue)
        writer.append(keyIdentifier)
        writer.append(signature)
        return writer.data
    }

    internal static func decode(_ data: Data) throws -> PeerNetworkAuthenticationProof {
        guard data.count <= maxEncodedByteLength else { throw PeerNetworkAuthenticationError.oversizedEncoding }
        var reader = PeerNetworkAuthenticationReader(data: data)
        guard try reader.readData(count: PeerNetworkAuthenticationEncoding.proofDomain.count)
            == PeerNetworkAuthenticationEncoding.proofDomain else {
            throw PeerNetworkAuthenticationError.malformedEncoding
        }
        let authenticationVersion = try reader.readUInt8()
        guard let algorithm = PeerNetworkAuthenticationAlgorithm(rawValue: try reader.readUInt8()) else {
            throw PeerNetworkAuthenticationError.invalidAlgorithm
        }
        guard let signerRole = PeerNetworkAuthenticationRole(rawValue: try reader.readUInt8()) else {
            throw PeerNetworkAuthenticationError.invalidRole
        }
        let keyIdentifier = try reader.readData(count: PeerPersistentSigningIdentity.keyIdentifierByteCount)
        let signature = try reader.readData(count: PeerPersistentSigningIdentity.signatureByteCount)
        guard reader.isAtEnd else { throw PeerNetworkAuthenticationError.malformedEncoding }
        let proof = try PeerNetworkAuthenticationProof(
            authenticationVersion: authenticationVersion,
            algorithm: algorithm,
            signerRole: signerRole,
            keyIdentifier: keyIdentifier,
            signature: signature)
        guard proof.encoded() == data else { throw PeerNetworkAuthenticationError.malformedEncoding }
        return proof
    }
}

private enum PeerNetworkAuthenticationEncoding {
    static let helloDomain = Data("PeerConnectivity.AuthHello.v1\0".utf8)
    static let transcriptDomain = Data("PeerConnectivity.AuthTranscript.v1\0".utf8)
    static let proofDomain = Data("PeerConnectivity.AuthProof.v1\0".utf8)
    static let signedProofDomain = Data("PeerConnectivity.AuthSignedProof.v1\0".utf8)
}

private struct PeerNetworkAuthenticationWriter {

    fileprivate var data = Data()

    fileprivate mutating func append(_ value: UInt8) {
        data.append(value)
    }

    fileprivate mutating func append(_ value: UInt16) {
        var bigEndianValue = value.bigEndian
        withUnsafeBytes(of: &bigEndianValue) { data.append(contentsOf: $0) }
    }

    fileprivate mutating func append(_ value: UInt32) {
        var bigEndianValue = value.bigEndian
        withUnsafeBytes(of: &bigEndianValue) { data.append(contentsOf: $0) }
    }

    fileprivate mutating func append(_ value: Data) {
        data.append(value)
    }

    fileprivate mutating func appendLengthPrefixed(_ value: String) {
        let valueData = Data(value.utf8)
        append(UInt16(valueData.count))
        append(valueData)
    }
}

private struct PeerNetworkAuthenticationReader {

    private let data : Data
    private var offset = 0

    fileprivate init(data: Data) {
        self.data = data
    }

    fileprivate var isAtEnd : Bool {
        return offset == data.count
    }

    fileprivate mutating func readUInt8() throws -> UInt8 {
        let bytes = try readData(count: 1)
        guard let value = bytes.first else { throw PeerNetworkAuthenticationError.malformedEncoding }
        return value
    }

    fileprivate mutating func readUInt16() throws -> UInt16 {
        return try readData(count: 2).reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
    }

    fileprivate mutating func readBoundedLength(maximum: Int) throws -> Int {
        let value = try readData(count: 4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard value <= UInt32(maximum) else { throw PeerNetworkAuthenticationError.oversizedEncoding }
        return Int(value)
    }

    fileprivate mutating func readString(maxByteLength: Int) throws -> String {
        let length = Int(try readUInt16())
        guard length > 0, length <= maxByteLength else {
            throw PeerNetworkAuthenticationError.malformedEncoding
        }
        let valueData = try readData(count: length)
        guard let value = String(data: valueData, encoding: .utf8) else {
            throw PeerNetworkAuthenticationError.malformedEncoding
        }
        return value
    }

    fileprivate mutating func readData(count: Int) throws -> Data {
        guard count >= 0, offset <= data.count, count <= data.count - offset else {
            throw PeerNetworkAuthenticationError.malformedEncoding
        }
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: count)
        offset += count
        return Data(data[start..<end])
    }
}
