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

        await observable.addObserverAsync { value in
            received.append(value)
        }

        XCTAssertEqual(received, [7])
    }

    func testObservableNotifiesObserversWhenValueChanges() async throws {
        let observable = Observable<String>("initial")
        var received : [String] = []

        await observable.addObserverAsync { value in
            received.append(value)
        }
        await observable.updateAsync("updated")

        XCTAssertEqual(received, ["initial", "updated"])
    }

    func testObservableSupportsMultipleObservers() async throws {
        let observable = Observable<Int>(0)
        var first : [Int] = []
        var second : [Int] = []

        await observable.addObserverAsync { value in
            first.append(value)
        }
        await observable.addObserverAsync { value in
            second.append(value)
        }
        await observable.updateAsync(1)

        XCTAssertEqual(first, [0, 1])
        XCTAssertEqual(second, [0, 1])
    }

    func testObservableImmediatelyNotifiesKeyedObserver() async throws {
        let observable = Observable<String>("ready")
        var received : [String] = []

        await observable.addObserverAsync({ value in
            received.append(value)
        }, key: "listener")

        XCTAssertEqual(received, ["ready"])
    }

    func testObservableReplacesObserverWithSameKey() async throws {
        let observable = Observable<Int>(1)
        var first : [Int] = []
        var replacement : [Int] = []

        await observable.addObserverAsync({ value in
            first.append(value)
        }, key: "duplicate")
        await observable.addObserverAsync({ value in
            replacement.append(value)
        }, key: "duplicate")
        await observable.updateAsync(2)

        XCTAssertEqual(first, [1])
        XCTAssertEqual(replacement, [1, 2])
    }

    func testObservableRemovesObserverForKey() async throws {
        let observable = Observable<Int>(1)
        var received : [Int] = []

        await observable.addObserverAsync({ value in
            received.append(value)
        }, key: "listener")
        await observable.removeObserverAsync(forKey: "listener")
        await observable.updateAsync(2)

        XCTAssertEqual(received, [1])
    }

    func testObservableNonisolatedAddObserverNotifiesObserver() async throws {
        let observable = Observable<Int>(3)
        let expectation = expectation(description: "observer notified")
        var received : [Int] = []

        observable.addObserver { value in
            received.append(value)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(received, [3])
    }
}
