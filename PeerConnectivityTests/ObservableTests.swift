//
//  ObservableTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 6/9/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import XCTest
@testable import PeerConnectivity

class ObservableTests: XCTestCase {

    // MARK: - Observable

    func testObservableImmediatelyNotifiesNewObserver() async throws {
        let observable = Observable<Int>(7)
        var received : [Int] = []

        observable.addObserver { value in
            received.append(value)
        }
        try await waitForObservableDelivery()

        XCTAssertEqual(received, [7])
    }

    func testObservableNotifiesObserversWhenValueChanges() async throws {
        let observable = Observable<String>("initial")
        var received : [String] = []

        observable.addObserver { value in
            received.append(value)
        }
        observable.update("updated")
        try await waitForObservableDelivery()

        XCTAssertEqual(received, ["initial", "updated"])
    }

    func testObservableSupportsMultipleObservers() async throws {
        let observable = Observable<Int>(0)
        var first : [Int] = []
        var second : [Int] = []

        observable.addObserver { value in
            first.append(value)
        }
        observable.addObserver { value in
            second.append(value)
        }
        observable.update(1)
        try await waitForObservableDelivery()

        XCTAssertEqual(first, [0, 1])
        XCTAssertEqual(second, [0, 1])
    }

    func testObservableImmediatelyNotifiesKeyedObserver() async throws {
        let observable = Observable<String>("ready")
        var received : [String] = []

        observable.addObserver({ value in
            received.append(value)
        }, key: "listener")
        try await waitForObservableDelivery()

        XCTAssertEqual(received, ["ready"])
    }

    func testObservableReplacesObserverWithSameKey() async throws {
        let observable = Observable<Int>(1)
        var first : [Int] = []
        var replacement : [Int] = []

        observable.addObserver({ value in
            first.append(value)
        }, key: "duplicate")
        observable.addObserver({ value in
            replacement.append(value)
        }, key: "duplicate")
        observable.update(2)
        try await waitForObservableDelivery()

        XCTAssertEqual(first, [1])
        XCTAssertEqual(replacement, [1, 2])
    }

    func testObservableRemovesObserverForKey() async throws {
        let observable = Observable<Int>(1)
        var received : [Int] = []

        observable.addObserver({ value in
            received.append(value)
        }, key: "listener")
        observable.removeObserver(forKey: "listener")
        observable.update(2)
        try await waitForObservableDelivery()

        XCTAssertEqual(received, [1])
    }

    private func waitForObservableDelivery() async throws {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}
