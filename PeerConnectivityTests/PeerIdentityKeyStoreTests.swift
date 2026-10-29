//
//  PeerIdentityKeyStoreTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 9/29/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
import CryptoKit
import Security
@testable import PeerConnectivity

private enum InMemoryIdentityKeyStoreError : Error {
    case loadFailed
    case addFailed
    case updateFailed
}

private final class ConcurrentInMemoryIdentityKeyStore : PeerIdentityKeyStoring {

    private let lock = NSLock()
    private var data : Data?

    internal func load() throws -> Data? {
        return lock.locked { data }
    }

    internal func add(_ data: Data) throws -> PeerIdentityKeyStoreAddResult {
        return lock.locked {
            guard self.data == nil else { return .duplicate }
            self.data = data
            return .inserted
        }
    }

    internal func update(_ data: Data) throws {
        try lock.locked {
            guard self.data != nil else { throw PeerIdentityKeyStoreError.missingItem }
            self.data = data
        }
    }
}

private final class SigningIdentityResults {

    private let lock = NSLock()
    private(set) var publicKeys : [Data] = []
    private(set) var errors : [Error] = []

    internal func append(_ result: Result<PeerPersistentSigningIdentity, Error>) {
        lock.locked {
            switch result {
            case .success(let identity):
                publicKeys.append(identity.publicKeyRepresentation)
            case .failure(let error):
                errors.append(error)
            }
        }
    }
}

private final class InMemoryIdentityKeyStore : PeerIdentityKeyStoring {

    internal var data : Data?
    internal var duplicateWinner : Data?
    internal var forceDuplicateWithoutWinner = false
    internal var updateTransform : ((Data) -> Data)?
    internal var loadError : Error?
    internal var addError : Error?
    internal var updateError : Error?
    internal private(set) var loadCount = 0
    internal private(set) var addCount = 0
    internal private(set) var updateCount = 0

    internal init(data: Data? = nil) {
        self.data = data
    }

    internal func load() throws -> Data? {
        loadCount += 1
        if let loadError = loadError { throw loadError }
        return data
    }

    internal func add(_ data: Data) throws -> PeerIdentityKeyStoreAddResult {
        addCount += 1
        if let addError = addError { throw addError }
        if forceDuplicateWithoutWinner { return .duplicate }
        if let duplicateWinner = duplicateWinner {
            self.data = duplicateWinner
            return .duplicate
        }
        guard self.data == nil else { return .duplicate }
        self.data = data
        return .inserted
    }

    internal func update(_ data: Data) throws {
        updateCount += 1
        if let updateError = updateError { throw updateError }
        guard self.data != nil else { throw PeerIdentityKeyStoreError.missingItem }
        self.data = updateTransform?(data) ?? data
    }
}

final class PeerIdentityKeyStoreTests : XCTestCase {

    internal func testLoadOrCreatePersistsStableIdentityAcrossStoreInstances() throws {
        let keyStore = InMemoryIdentityKeyStore()
        let first = try PeerPersistentSigningIdentityStore(keyStore: keyStore).loadOrCreate()
        let second = try PeerPersistentSigningIdentityStore(keyStore: keyStore).loadOrCreate()

        XCTAssertEqual(first.publicKeyRepresentation, second.publicKeyRepresentation)
        XCTAssertEqual(first.keyIdentifier, second.keyIdentifier)
        XCTAssertEqual(keyStore.addCount, 1)
        XCTAssertEqual(keyStore.updateCount, 0)
    }

    internal func testConcurrentFirstUseReturnsOnePersistedIdentity() {
        let keyStore = ConcurrentInMemoryIdentityKeyStore()
        let results = SigningIdentityResults()

        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            results.append(Result {
                try PeerPersistentSigningIdentityStore(keyStore: keyStore).loadOrCreate()
            })
        }

        XCTAssertTrue(results.errors.isEmpty)
        XCTAssertEqual(results.publicKeys.count, 32)
        XCTAssertEqual(Set(results.publicKeys).count, 1)
    }

    internal func testDuplicateAddLoadsAtomicWinner() throws {
        let winner = try storedIdentityFixture()
        let keyStore = InMemoryIdentityKeyStore()
        keyStore.duplicateWinner = winner.data

        let identity = try PeerPersistentSigningIdentityStore(keyStore: keyStore).loadOrCreate()

        XCTAssertEqual(identity.publicKeyRepresentation, winner.identity.publicKeyRepresentation)
        XCTAssertEqual(keyStore.addCount, 1)
        XCTAssertEqual(keyStore.loadCount, 2)
    }

    internal func testDuplicateWithoutWinnerFailsClosed() {
        let keyStore = InMemoryIdentityKeyStore()
        keyStore.forceDuplicateWithoutWinner = true

        XCTAssertThrowsError(try PeerPersistentSigningIdentityStore(keyStore: keyStore).loadOrCreate()) { error in
            XCTAssertEqual(error as? PeerPersistentSigningIdentityError, .duplicateWithoutWinner)
        }
    }

    internal func testCorruptStoredPrivateKeyFailsWithoutRotation() {
        let keyStore = InMemoryIdentityKeyStore(data: Data(repeating: 7, count: 31))

        XCTAssertThrowsError(try PeerPersistentSigningIdentityStore(keyStore: keyStore).loadOrCreate()) { error in
            XCTAssertEqual(error as? PeerPersistentSigningIdentityError, .corruptPrivateKey)
        }
        XCTAssertEqual(keyStore.addCount, 0)
        XCTAssertEqual(keyStore.updateCount, 0)
    }

    internal func testStoredPrivateKeySegmentMutationFailsClosed() throws {
        var stored = try storedIdentityFixture().data
        let privateKeyOffset = Data("PeerConnectivity.IdentityKey.v1\0".utf8).count
        let mutationIndex = stored.index(stored.startIndex, offsetBy: privateKeyOffset + 5)
        stored[mutationIndex] ^= 0x01
        let keyStore = InMemoryIdentityKeyStore(data: stored)

        XCTAssertThrowsError(try PeerPersistentSigningIdentityStore(keyStore: keyStore).loadOrCreate()) { error in
            XCTAssertEqual(error as? PeerPersistentSigningIdentityError, .corruptPrivateKey)
        }
        XCTAssertEqual(keyStore.addCount, 0)
        XCTAssertEqual(keyStore.updateCount, 0)
    }

    internal func testLoadAccessFailureFailsClosed() {
        let keyStore = InMemoryIdentityKeyStore()
        keyStore.loadError = InMemoryIdentityKeyStoreError.loadFailed

        XCTAssertThrowsError(try PeerPersistentSigningIdentityStore(keyStore: keyStore).loadOrCreate())
        XCTAssertEqual(keyStore.addCount, 0)
    }

    internal func testAddAccessFailureFailsClosed() {
        let keyStore = InMemoryIdentityKeyStore()
        keyStore.addError = InMemoryIdentityKeyStoreError.addFailed

        XCTAssertThrowsError(try PeerPersistentSigningIdentityStore(keyStore: keyStore).loadOrCreate())
        XCTAssertNil(keyStore.data)
    }

    internal func testRotationUsesUpdateAndChangesPersistedIdentity() throws {
        let keyStore = InMemoryIdentityKeyStore(data: try storedIdentityFixture().data)
        let identityStore = PeerPersistentSigningIdentityStore(keyStore: keyStore)
        let original = try identityStore.loadOrCreate()

        let replacement = try identityStore.rotate()
        let reloaded = try identityStore.loadOrCreate()

        XCTAssertNotEqual(original.publicKeyRepresentation, replacement.publicKeyRepresentation)
        XCTAssertEqual(replacement.publicKeyRepresentation, reloaded.publicKeyRepresentation)
        XCTAssertEqual(keyStore.addCount, 0)
        XCTAssertEqual(keyStore.updateCount, 1)
    }

    internal func testRotationRequiresValidExistingItem() {
        let missingStore = InMemoryIdentityKeyStore()
        XCTAssertThrowsError(try PeerPersistentSigningIdentityStore(keyStore: missingStore).rotate()) { error in
            XCTAssertEqual(error as? PeerIdentityKeyStoreError, .missingItem)
        }
        XCTAssertEqual(missingStore.updateCount, 0)

        let corruptStore = InMemoryIdentityKeyStore(data: Data(repeating: 8, count: 33))
        XCTAssertThrowsError(try PeerPersistentSigningIdentityStore(keyStore: corruptStore).rotate())
        XCTAssertEqual(corruptStore.updateCount, 0)
    }

    internal func testRotationFailsWhenPostUpdateReadbackDoesNotMatch() throws {
        let original = try storedIdentityFixture()
        let keyStore = InMemoryIdentityKeyStore(data: original.data)
        keyStore.updateTransform = { _ in original.data }

        XCTAssertThrowsError(try PeerPersistentSigningIdentityStore(keyStore: keyStore).rotate()) { error in
            XCTAssertEqual(error as? PeerPersistentSigningIdentityError, .postUpdateMismatch)
        }
        XCTAssertEqual(keyStore.updateCount, 1)
        XCTAssertEqual(keyStore.addCount, 0)
    }

    internal func testRotationUpdateFailureDoesNotFallBackToAdd() throws {
        let keyStore = InMemoryIdentityKeyStore(data: try storedIdentityFixture().data)
        keyStore.updateError = InMemoryIdentityKeyStoreError.updateFailed

        XCTAssertThrowsError(try PeerPersistentSigningIdentityStore(keyStore: keyStore).rotate())
        XCTAssertEqual(keyStore.updateCount, 1)
        XCTAssertEqual(keyStore.addCount, 0)
    }

    internal func testExplicitRecoveryReplacesCorruptItemWithUpdate() throws {
        let keyStore = InMemoryIdentityKeyStore(data: Data(repeating: 8, count: 33))
        let identityStore = PeerPersistentSigningIdentityStore(keyStore: keyStore)

        XCTAssertThrowsError(try identityStore.loadOrCreate())
        let recovered = try identityStore.replaceIdentityForRecovery()
        let reloaded = try identityStore.loadOrCreate()

        XCTAssertEqual(recovered.publicKeyRepresentation, reloaded.publicKeyRepresentation)
        XCTAssertEqual(keyStore.addCount, 0)
        XCTAssertEqual(keyStore.updateCount, 1)
    }

    internal func testExplicitRecoveryRejectsInvalidKeychainProtection() {
        let keyStore = InMemoryIdentityKeyStore(data: Data(repeating: 8, count: 33))
        keyStore.loadError = PeerIdentityKeyStoreError.invalidProtection

        XCTAssertThrowsError(try PeerPersistentSigningIdentityStore(
            keyStore: keyStore).replaceIdentityForRecovery()) { error in
                XCTAssertEqual(error as? PeerIdentityKeyStoreError, .invalidProtection)
            }
        XCTAssertEqual(keyStore.addCount, 0)
        XCTAssertEqual(keyStore.updateCount, 0)
    }

    internal func testExplicitRecoveryFailureDoesNotAddFallback() {
        let keyStore = InMemoryIdentityKeyStore(data: Data(repeating: 8, count: 33))
        keyStore.updateError = InMemoryIdentityKeyStoreError.updateFailed

        XCTAssertThrowsError(try PeerPersistentSigningIdentityStore(
            keyStore: keyStore).replaceIdentityForRecovery())
        XCTAssertEqual(keyStore.addCount, 0)
        XCTAssertEqual(keyStore.updateCount, 1)
    }

    internal func testCryptoKitIdentitySignsOnlyForMatchingPublicKey() throws {
        let identity = PeerPersistentSigningIdentity()
        let otherIdentity = PeerPersistentSigningIdentity()
        let message = Data("authenticated transcript".utf8)
        let signature = try identity.signature(for: message)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: identity.publicKeyRepresentation)
        let otherPublicKey = try Curve25519.Signing.PublicKey(rawRepresentation: otherIdentity.publicKeyRepresentation)

        XCTAssertTrue(publicKey.isValidSignature(signature, for: message))
        XCTAssertFalse(otherPublicKey.isValidSignature(signature, for: message))
        XCTAssertEqual(identity.keyIdentifier.count, PeerPersistentSigningIdentity.keyIdentifierByteCount)
    }

    internal func testKeychainStoreRequiresExplicitBoundedNamespaces() {
        XCTAssertThrowsError(try PeerIdentityKeychainStore(applicationNamespace: "", serviceNamespace: "service"))
        XCTAssertThrowsError(try PeerIdentityKeychainStore(applicationNamespace: "app", serviceNamespace: ""))
        XCTAssertThrowsError(try PeerIdentityKeychainStore(
            applicationNamespace: String(repeating: "a", count: 256),
            serviceNamespace: "service"))
    }

    internal func testKeychainLoadQueryRequestsDataAndProtectionAttributes() throws {
        let store = try PeerIdentityKeychainStore(
            applicationNamespace: "com.example.identity-tests",
            serviceNamespace: "local")
        let query = store.loadQuery

        XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitAll as String)
        XCTAssertEqual(query[kSecReturnAttributes as String] as? Bool, true)
        XCTAssertEqual(query[kSecReturnData as String] as? Bool, true)
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        #if os(macOS)
        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
        #endif
    }

    internal func testKeychainLoadRejectsWeakerOrSynchronizableProtection() throws {
        let store = try PeerIdentityKeychainStore(
            applicationNamespace: "com.example.identity-tests",
            serviceNamespace: "local")
        let value = Data(repeating: 7, count: 32)
        var attributes : [String:Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]

        XCTAssertEqual(try store.validatedData(from: attributes as CFDictionary), value)

        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        XCTAssertThrowsError(try store.validatedData(from: attributes as CFDictionary)) { error in
            XCTAssertEqual(error as? PeerIdentityKeyStoreError, .invalidProtection)
        }

        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = true
        XCTAssertThrowsError(try store.validatedData(from: attributes as CFDictionary)) { error in
            XCTAssertEqual(error as? PeerIdentityKeyStoreError, .invalidProtection)
        }

        attributes.removeValue(forKey: kSecAttrSynchronizable as String)
        XCTAssertEqual(try store.validatedData(from: attributes as CFDictionary), value)

        attributes[kSecAttrSynchronizable as String] = "not-a-boolean"
        XCTAssertThrowsError(try store.validatedData(from: attributes as CFDictionary)) { error in
            XCTAssertEqual(error as? PeerIdentityKeyStoreError, .invalidProtection)
        }

        let validAttributes : [String:Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        let synchronizableAttributes : [String:Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: true,
        ]
        XCTAssertThrowsError(try store.validatedData(
            from: [validAttributes, synchronizableAttributes] as CFArray)) { error in
                XCTAssertEqual(error as? PeerIdentityKeyStoreError, .invalidProtection)
            }
    }

    internal func testKeychainStoreUsesGenericPasswordDeviceOnlyNonSynchronizingNamespace() throws {
        let store = try PeerIdentityKeychainStore(
            applicationNamespace: "com.example.identity-tests",
            serviceNamespace: "local")
        let value = Data(repeating: 9, count: 32)
        let query = store.addQuery(for: value)

        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "com.example.identity-tests")
        XCTAssertEqual(
            query[kSecAttrAccount as String] as? String,
            "PeerConnectivity.NetworkIdentity.local")
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(
            query[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(query[kSecValueData as String] as? Data, value)
        #if os(macOS)
        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
        #endif
    }

    /// Creates a valid versioned storage record without exposing production private-key APIs.
    private func storedIdentityFixture() throws -> (data: Data, identity: PeerPersistentSigningIdentity) {
        let keyStore = InMemoryIdentityKeyStore()
        let identity = try PeerPersistentSigningIdentityStore(keyStore: keyStore).loadOrCreate()
        return (try XCTUnwrap(keyStore.data), identity)
    }
}
