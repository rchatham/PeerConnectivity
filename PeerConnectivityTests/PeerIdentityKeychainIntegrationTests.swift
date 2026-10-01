//
//  PeerIdentityKeychainIntegrationTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 9/29/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

#if os(macOS) || (os(iOS) && targetEnvironment(simulator))
// Real Keychain access needs an entitled host; hostless test runners may skip these tests.
import XCTest
import Security
@testable import PeerConnectivity

final class PeerIdentityKeychainIntegrationTests : XCTestCase {

    private var cleanupQueries : [[String:Any]] = []

    override internal func tearDown() {
        cleanupQueries.forEach { query in
            let status = SecItemDelete(query as CFDictionary)
            XCTAssertTrue(
                status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement,
                "Unexpected test-only Keychain cleanup status: \(status)")
        }
        cleanupQueries.removeAll()
        super.tearDown()
    }

    internal func testRealKeychainPersistsAndRotatesOnlyTestNamespaceIdentity() throws {
        let suffix = UUID().uuidString
        let applicationNamespace = "com.rchatham.PeerConnectivityTests.\(suffix)"
        let serviceNamespace = "integration-\(suffix)"
        let keychainStore = try PeerIdentityKeychainStore(
            applicationNamespace: applicationNamespace,
            serviceNamespace: serviceNamespace)
        cleanupQueries.append(cleanupQuery(for: keychainStore))

        let first : PeerPersistentSigningIdentity
        do {
            first = try PeerPersistentSigningIdentityStore(
                applicationNamespace: applicationNamespace,
                serviceNamespace: serviceNamespace).loadOrCreate()
        } catch PeerIdentityKeyStoreError.unexpectedStatus(errSecMissingEntitlement) {
            throw XCTSkip("Test runner lacks a usable Keychain entitlement (errSecMissingEntitlement)")
        }
        let reloaded = try PeerPersistentSigningIdentityStore(
            applicationNamespace: applicationNamespace,
            serviceNamespace: serviceNamespace).loadOrCreate()
        XCTAssertEqual(first.publicKeyRepresentation, reloaded.publicKeyRepresentation)

        let rotated = try PeerPersistentSigningIdentityStore(
            applicationNamespace: applicationNamespace,
            serviceNamespace: serviceNamespace).rotate()
        let reloadedAfterRotation = try PeerPersistentSigningIdentityStore(
            applicationNamespace: applicationNamespace,
            serviceNamespace: serviceNamespace).loadOrCreate()
        XCTAssertNotEqual(first.publicKeyRepresentation, rotated.publicKeyRepresentation)
        XCTAssertEqual(rotated.publicKeyRepresentation, reloadedAfterRotation.publicKeyRepresentation)
    }

    #if os(iOS)
    internal func testSimulatorKeychainDoesNotLoadSynchronizableIdentity() throws {
        let suffix = UUID().uuidString
        let keychainStore = try PeerIdentityKeychainStore(
            applicationNamespace: "com.rchatham.PeerConnectivityTests.\(suffix)",
            serviceNamespace: "simulator-\(suffix)")
        cleanupQueries.append(cleanupQuery(for: keychainStore))
        let originalData = Data(repeating: 0x5A, count: 32)
        var addQuery = keychainStore.addQuery(for: originalData)
        addQuery[kSecAttrSynchronizable as String] = true
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecMissingEntitlement {
            throw XCTSkip("Hostless simulator XCTest bundle has no usable Keychain application entitlement")
        }
        XCTAssertEqual(addStatus, errSecSuccess)

        // The non-sync query must not adopt a synchronizable item, even if returned attributes omit the flag.
        XCTAssertNil(try keychainStore.load())

        var syncQuery = keychainStore.loadQuery
        syncQuery[kSecAttrSynchronizable as String] = true
        var result : CFTypeRef?
        let status = SecItemCopyMatching(syncQuery as CFDictionary, &result)
        XCTAssertEqual(status, errSecSuccess)
        let items = try XCTUnwrap(result as? [[String:Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?[kSecValueData as String] as? Data, originalData)
        XCTAssertEqual(items.first?[kSecAttrSynchronizable as String] as? Bool, true)
    }
    #endif

    #if os(macOS)
    internal func testMacOSDataProtectionKeychainPersistsTestOnlyItem() throws {
        let suffix = UUID().uuidString
        let store = try PeerIdentityKeychainStore(
            applicationNamespace: "com.rchatham.PeerConnectivityTests.\(suffix)",
            serviceNamespace: "macos-dp-\(suffix)")
        cleanupQueries.append(cleanupQuery(for: store))
        XCTAssertEqual(store.loadQuery[kSecUseDataProtectionKeychain as String] as? Bool, true)

        let payload = Data("macos-dp-test-only".utf8)
        let addResult : PeerIdentityKeyStoreAddResult
        do {
            addResult = try store.add(payload)
        } catch PeerIdentityKeyStoreError.unexpectedStatus(errSecMissingEntitlement) {
            throw XCTSkip("macOS Data Protection Keychain requires an entitlement unavailable to this test runner (-34018)")
        }
        XCTAssertEqual(addResult, .inserted)
        let reloaded = try PeerIdentityKeychainStore(
            applicationNamespace: store.namespace.application,
            serviceNamespace: store.namespace.service).load()
        XCTAssertEqual(reloaded, payload)
    }
    #endif

    /// Deletes every test-only item for one exact application/service namespace, including sync variants.
    private func cleanupQuery(for store: PeerIdentityKeychainStore) -> [String:Any] {
        var query = store.namespaceQuery
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        return query
    }
}
#endif
