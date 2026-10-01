//
//  PeerIdentityKeyStore.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 9/29/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import CryptoKit
import Security

internal enum PeerIdentityKeyStoreAddResult : Equatable {
    case inserted
    case duplicate
}

internal protocol PeerIdentityKeyStoring {
    func load() throws -> Data?
    func add(_ data: Data) throws -> PeerIdentityKeyStoreAddResult
    func update(_ data: Data) throws
}

internal enum PeerIdentityKeyStoreError : Error, Equatable {
    case invalidApplicationNamespace
    case invalidServiceNamespace
    case invalidResult
    case invalidProtection
    case missingItem
    case unexpectedStatus(OSStatus)
}

internal struct PeerIdentityKeychainNamespace : Equatable {

    internal static let maxNamespaceByteLength = 255

    internal let application : String
    internal let service : String

    internal init(application: String, service: String) throws {
        guard PeerIdentityKeychainNamespace.isValid(application) else {
            throw PeerIdentityKeyStoreError.invalidApplicationNamespace
        }
        guard PeerIdentityKeychainNamespace.isValid(service) else {
            throw PeerIdentityKeyStoreError.invalidServiceNamespace
        }
        self.application = application
        self.service = service
    }

    fileprivate var keychainService : String {
        return application
    }

    fileprivate var keychainAccount : String {
        return "PeerConnectivity.NetworkIdentity.\(service)"
    }

    private static func isValid(_ value: String) -> Bool {
        return !value.isEmpty && value.utf8.count <= maxNamespaceByteLength
    }
}

internal final class PeerIdentityKeychainStore : PeerIdentityKeyStoring {

    internal let namespace : PeerIdentityKeychainNamespace

    internal init(applicationNamespace: String, serviceNamespace: String) throws {
        namespace = try PeerIdentityKeychainNamespace(
            application: applicationNamespace,
            service: serviceNamespace)
    }

    internal func load() throws -> Data? {
        var result : CFTypeRef?
        let status = SecItemCopyMatching(loadQuery as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return try validatedData(from: result)
        case errSecItemNotFound:
            return nil
        default:
            throw PeerIdentityKeyStoreError.unexpectedStatus(status)
        }
    }

    internal func add(_ data: Data) throws -> PeerIdentityKeyStoreAddResult {
        let query = addQuery(for: data)
        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return .inserted
        case errSecDuplicateItem:
            return .duplicate
        default:
            throw PeerIdentityKeyStoreError.unexpectedStatus(status)
        }
    }

    internal func update(_ data: Data) throws {
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            throw PeerIdentityKeyStoreError.missingItem
        default:
            throw PeerIdentityKeyStoreError.unexpectedStatus(status)
        }
    }

    internal func addQuery(for data: Data) -> [String:Any] {
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return query
    }

    internal var loadQuery : [String:Any] {
        // Filter at the Keychain boundary: omitted return attributes cannot prove an item is non-synchronizing.
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        return query
    }

    internal func validatedData(from result: CFTypeRef?) throws -> Data {
        if let attributes = result as? [String:Any] {
            return try validatedData(from: attributes)
        }
        guard let items = result as? [[String:Any]], !items.isEmpty else {
            throw PeerIdentityKeyStoreError.invalidResult
        }
        let validatedItems = try items.map(validatedData(from:))
        guard validatedItems.count == 1, let data = validatedItems.first else {
            throw PeerIdentityKeyStoreError.invalidResult
        }
        return data
    }

    internal var baseQuery : [String:Any] {
        var query = namespaceQuery
        query[kSecAttrSynchronizable as String] = false
        return query
    }

    internal var namespaceQuery : [String:Any] {
        var query : [String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: namespace.keychainService,
            kSecAttrAccount as String: namespace.keychainAccount,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    private func validatedData(from attributes: [String:Any]) throws -> Data {
        guard let data = attributes[kSecValueData as String] as? Data else {
            throw PeerIdentityKeyStoreError.invalidResult
        }
        guard attributes[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String else {
            throw PeerIdentityKeyStoreError.invalidProtection
        }
        // Keychain may omit false in returned attributes. The load query itself selects only false.
        if let returnedValue = attributes[kSecAttrSynchronizable as String] {
            guard let synchronizable = returnedValue as? Bool, !synchronizable else {
                throw PeerIdentityKeyStoreError.invalidProtection
            }
        }
        return data
    }
}

internal protocol PeerIdentitySigning {
    var publicKeyRepresentation : Data { get }
    var keyIdentifier : Data { get }
    func signature(for data: Data) throws -> Data
}

internal enum PeerPersistentSigningIdentityError : Error, Equatable {
    case corruptPrivateKey
    case duplicateWithoutWinner
    case postUpdateMismatch
}

internal struct PeerPersistentSigningIdentity : PeerIdentitySigning {

    internal static let publicKeyByteCount = 32
    internal static let keyIdentifierByteCount = 32
    internal static let signatureByteCount = 64
    private static let storageDomain = Data("PeerConnectivity.IdentityKey.v1\0".utf8)

    fileprivate let privateKey : Curve25519.Signing.PrivateKey

    internal init() {
        privateKey = Curve25519.Signing.PrivateKey()
    }

    fileprivate init(storageRepresentation: Data) throws {
        let expectedByteCount = PeerPersistentSigningIdentity.storageDomain.count
            + PeerPersistentSigningIdentity.publicKeyByteCount * 3
        guard storageRepresentation.count == expectedByteCount,
            storageRepresentation.starts(with: PeerPersistentSigningIdentity.storageDomain) else {
            throw PeerPersistentSigningIdentityError.corruptPrivateKey
        }

        var offset = PeerPersistentSigningIdentity.storageDomain.count
        let privateKeyData = storageRepresentation.subdata(
            in: offset..<(offset + PeerPersistentSigningIdentity.publicKeyByteCount))
        offset += PeerPersistentSigningIdentity.publicKeyByteCount
        let storedPublicKey = storageRepresentation.subdata(
            in: offset..<(offset + PeerPersistentSigningIdentity.publicKeyByteCount))
        offset += PeerPersistentSigningIdentity.publicKeyByteCount
        let storedKeyIdentifier = storageRepresentation.subdata(
            in: offset..<(offset + PeerPersistentSigningIdentity.keyIdentifierByteCount))

        do {
            privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        } catch {
            throw PeerPersistentSigningIdentityError.corruptPrivateKey
        }
        guard publicKeyRepresentation == storedPublicKey,
            keyIdentifier == storedKeyIdentifier else {
            throw PeerPersistentSigningIdentityError.corruptPrivateKey
        }
    }

    internal var publicKeyRepresentation : Data {
        return privateKey.publicKey.rawRepresentation
    }

    internal var keyIdentifier : Data {
        return PeerPersistentSigningIdentity.keyIdentifier(for: publicKeyRepresentation)
    }

    internal func signature(for data: Data) throws -> Data {
        return try privateKey.signature(for: data)
    }

    internal static func keyIdentifier(for publicKeyRepresentation: Data) -> Data {
        var input = Data("PeerConnectivity.NetworkIdentity.Curve25519Signing.KeyID.v1".utf8)
        input.append(publicKeyRepresentation)
        return Data(SHA256.hash(data: input))
    }

    fileprivate var storageRepresentation : Data {
        var data = PeerPersistentSigningIdentity.storageDomain
        data.append(privateKey.rawRepresentation)
        data.append(publicKeyRepresentation)
        data.append(keyIdentifier)
        return data
    }
}

internal final class PeerPersistentSigningIdentityStore {

    private let keyStore : PeerIdentityKeyStoring
    private let identityGenerator : () -> PeerPersistentSigningIdentity
    private let lock = NSLock()

    internal convenience init(applicationNamespace: String, serviceNamespace: String) throws {
        let keyStore = try PeerIdentityKeychainStore(
            applicationNamespace: applicationNamespace,
            serviceNamespace: serviceNamespace)
        self.init(keyStore: keyStore)
    }

    internal init(
        keyStore: PeerIdentityKeyStoring,
        identityGenerator: @escaping () -> PeerPersistentSigningIdentity = PeerPersistentSigningIdentity.init
    ) {
        self.keyStore = keyStore
        self.identityGenerator = identityGenerator
    }

    internal func loadOrCreate() throws -> PeerPersistentSigningIdentity {
        return try lock.locked {
            if let identity = try loadIdentity() {
                return identity
            }

            let candidate = identityGenerator()
            switch try keyStore.add(candidate.storageRepresentation) {
            case .inserted:
                return candidate
            case .duplicate:
                guard let winner = try loadIdentity() else {
                    throw PeerPersistentSigningIdentityError.duplicateWithoutWinner
                }
                return winner
            }
        }
    }

    /// The caller must serialize rotation for each namespace, including across processes.
    /// Readback detects an observed race but cannot guarantee the identity remains current after return.
    /// A changed key identifier requires app reapproval.
    internal func rotate() throws -> PeerPersistentSigningIdentity {
        return try lock.locked {
            guard try loadIdentity() != nil else { throw PeerIdentityKeyStoreError.missingItem }
            return try replaceStoredIdentity()
        }
    }

    /// Explicitly replaces an unreadable identity. Call only after recovery approval; pins to the old key become invalid.
    internal func replaceIdentityForRecovery() throws -> PeerPersistentSigningIdentity {
        return try lock.locked {
            guard try keyStore.load() != nil else { throw PeerIdentityKeyStoreError.missingItem }
            return try replaceStoredIdentity()
        }
    }

    private func replaceStoredIdentity() throws -> PeerPersistentSigningIdentity {
        let replacement = identityGenerator()
        try keyStore.update(replacement.storageRepresentation)
        guard let persisted = try loadIdentity(),
            persisted.publicKeyRepresentation == replacement.publicKeyRepresentation,
            persisted.keyIdentifier == replacement.keyIdentifier else {
            throw PeerPersistentSigningIdentityError.postUpdateMismatch
        }
        return persisted
    }

    private func loadIdentity() throws -> PeerPersistentSigningIdentity? {
        guard let data = try keyStore.load() else { return nil }
        return try PeerPersistentSigningIdentity(storageRepresentation: data)
    }
}
