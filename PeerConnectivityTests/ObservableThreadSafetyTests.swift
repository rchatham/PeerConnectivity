//
//  ObservableThreadSafetyTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 7/21/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
@testable import PeerConnectivity

final class ObservableThreadSafetyTests: XCTestCase {

    // MARK: - Observable

    func testObservableAllowsConcurrentObserversAndValueUpdates() {
        let observable = Observable<Int>(0)
        let queue = DispatchQueue(label: "PeerConnectivity.ObservableThreadSafetyTests.observable", attributes: .concurrent)
        let group = DispatchGroup()
        let delivery = expectation(description: "observer delivered")
        delivery.expectedFulfillmentCount = 100
        delivery.assertForOverFulfill = false

        for index in 0..<100 {
            group.enter()
            queue.async {
                observable.addObserver { _ in
                    delivery.fulfill()
                }
                observable.update(index)
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        wait(for: [delivery], timeout: 5)
    }

    func testObservableAllowsConcurrentKeyedObserversAndValueUpdates() {
        let observable = Observable<Int>(0)
        let queue = DispatchQueue(label: "PeerConnectivity.ObservableThreadSafetyTests.keyedObservable", attributes: .concurrent)
        let group = DispatchGroup()
        let delivery = expectation(description: "keyed observer delivered")
        delivery.expectedFulfillmentCount = 100
        delivery.assertForOverFulfill = false

        for index in 0..<100 {
            group.enter()
            queue.async {
                observable.addObserver({ _ in
                    delivery.fulfill()
                }, key: "observer-\(index)")
                observable.update(index)
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        wait(for: [delivery], timeout: 5)
    }

    func testObservableAllowsObserverRemovalDuringDelivery() {
        let observable = Observable<Int>(0)
        let delivery = expectation(description: "observer delivered")
        delivery.assertForOverFulfill = false

        observable.addObserver({ _ in
            observable.removeObserver(forKey: "self-removing")
            delivery.fulfill()
        }, key: "self-removing")

        observable.update(1)

        wait(for: [delivery], timeout: 1)
    }

    // MARK: - PeerConnectionResponder

    func testResponderAllowsConcurrentListenerRemovalAndEventDelivery() {
        let observable = Observable<PeerConnectionEvent>(.ready)
        let responder = PeerConnectionResponder(observer: observable)
        let queue = DispatchQueue(label: "PeerConnectivity.ObservableThreadSafetyTests.responder", attributes: .concurrent)
        let group = DispatchGroup()
        let delivery = expectation(description: "listener delivered")
        delivery.expectedFulfillmentCount = 100
        delivery.assertForOverFulfill = false

        for index in 0..<100 {
            group.enter()
            queue.async {
                responder.addListener({ _ in
                    delivery.fulfill()
                }, forKey: "listener-\(index)")
                observable.update(.started)
                responder.removeListenerForKey("listener-\(index)")
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        wait(for: [delivery], timeout: 5)
    }
}
