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
        let lock = NSLock()
        var deliveryCount = 0

        for index in 0..<100 {
            group.enter()
            queue.async {
                observable.addObserver { _ in
                    lock.lock()
                    deliveryCount += 1
                    lock.unlock()
                }
                observable.value = index
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertGreaterThan(deliveryCount, 0)
    }

    // MARK: - MultiObservable

    func testMultiObservableAllowsConcurrentObserversAndValueUpdates() {
        let observable = MultiObservable<Int>(0)
        let queue = DispatchQueue(label: "PeerConnectivity.ObservableThreadSafetyTests.multiObservable", attributes: .concurrent)
        let group = DispatchGroup()
        let lock = NSLock()
        var deliveryCount = 0

        for index in 0..<100 {
            group.enter()
            queue.async {
                observable.addObserver({ _ in
                    lock.lock()
                    deliveryCount += 1
                    lock.unlock()
                }, key: "observer-\(index)")
                observable.value = index
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertGreaterThan(deliveryCount, 0)
    }

    func testMultiObservableAllowsObserverRemovalDuringDelivery() {
        let observable = MultiObservable<Int>(0)
        let delivery = expectation(description: "observer delivered")

        observable.addObserver({ _ in
            observable.removeObserverForkey("self-removing")
            delivery.fulfill()
        }, key: "self-removing")

        observable.value = 1

        wait(for: [delivery], timeout: 1)
        XCTAssertTrue(observable.observers.isEmpty)
    }

    // MARK: - PeerConnectionResponder

    func testResponderAllowsConcurrentListenerRemovalAndEventDelivery() {
        let observable = MultiObservable<PeerConnectionEvent>(.ready)
        let responder = PeerConnectionResponder(observer: observable)
        let queue = DispatchQueue(label: "PeerConnectivity.ObservableThreadSafetyTests.responder", attributes: .concurrent)
        let group = DispatchGroup()
        let lock = NSLock()
        var deliveryCount = 0

        for index in 0..<100 {
            group.enter()
            queue.async {
                responder.addListener({ _ in
                    lock.lock()
                    deliveryCount += 1
                    lock.unlock()
                }, forKey: "listener-\(index)")
                observable.value = .started
                responder.removeListenerForKey("listener-\(index)")
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertGreaterThan(deliveryCount, 0)
    }
}
