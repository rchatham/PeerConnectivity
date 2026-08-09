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

    func testObservableImmediatelyNotifiesNewObserver() {
        let observable = Observable<Int>(7)
        var received : [Int] = []

        observable.addObserver { value in
            received.append(value)
        }

        XCTAssertEqual(received, [7])
    }

    func testObservableNotifiesObserversWhenValueChanges() {
        let observable = Observable<String>("initial")
        var received : [String] = []

        observable.addObserver { value in
            received.append(value)
        }
        observable.value = "updated"

        XCTAssertEqual(received, ["initial", "updated"])
    }

    func testObservableSupportsMultipleObservers() {
        let observable = Observable<Int>(0)
        var first : [Int] = []
        var second : [Int] = []

        observable.addObserver { value in
            first.append(value)
        }
        observable.addObserver { value in
            second.append(value)
        }
        observable.value = 1

        XCTAssertEqual(first, [0, 1])
        XCTAssertEqual(second, [0, 1])
    }

    // MARK: - MultiObservable

    func testMultiObservableImmediatelyNotifiesNewObserver() {
        let observable = MultiObservable<String>("ready")
        var received : [String] = []

        observable.addObserver({ value in
            received.append(value)
        }, key: "listener")

        XCTAssertEqual(received, ["ready"])
    }

    func testMultiObservableReplacesObserverWithSameKey() {
        let observable = MultiObservable<Int>(1)
        var first : [Int] = []
        var replacement : [Int] = []

        observable.addObserver({ value in
            first.append(value)
        }, key: "duplicate")
        observable.addObserver({ value in
            replacement.append(value)
        }, key: "duplicate")
        observable.value = 2

        XCTAssertEqual(first, [1])
        XCTAssertEqual(replacement, [1, 2])
    }

    func testMultiObservableRemovesObserverForKey() {
        let observable = MultiObservable<Int>(1)
        var received : [Int] = []

        observable.addObserver({ value in
            received.append(value)
        }, key: "listener")
        observable.removeObserverForkey("listener")
        observable.value = 2

        XCTAssertEqual(received, [1])
    }
}
