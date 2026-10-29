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

    func testBoundedParallelUpdatesHaveNoLossDuplicatesOrPermitLeaks() async {
        for _ in 0..<20 {
            let observable = Observable<Int>(0, boundedCapacity: 3)
            var received : [Int] = []
            await observable.addObserverAsync({ [weak observable] value in
                received.append(value)
                if let counts = observable?.boundedSubmissionCounts {
                    XCTAssertTrue(counts.admitted <= 3)
                }
            }, replayCurrentValue: false)

            await withTaskGroup(of: (Int, Bool).self) { group in
                for value in 1...48 {
                    group.addTask { (value, await observable.updateBoundedAsync(value)) }
                }
                var submitted : [Int] = []
                for await (value, processed) in group {
                    XCTAssertTrue(processed)
                    submitted.append(value)
                }
                XCTAssertEqual(submitted.sorted(), Array(1...48))
            }
            await observable.flush()
            XCTAssertEqual(received.sorted(), Array(1...48))
            XCTAssertEqual(observable.boundedSubmissionCounts.admitted, 0)
            XCTAssertEqual(observable.boundedSubmissionCounts.waiting, 0)
        }
    }

    func testBoundedParallelCancellationReportsExactlyProcessedUpdates() async {
        for _ in 0..<20 {
            let observable = Observable<Int>(0, boundedCapacity: 2)
            var received : [Int] = []
            await observable.addObserverAsync({ received.append($0) }, replayCurrentValue: false)

            let tasks = (1...32).map { value in
                (value, Task { await observable.updateBoundedAsync(value) })
            }
            for (value, task) in tasks where value.isMultiple(of: 2) {
                task.cancel()
            }
            var processed : [Int] = []
            for (value, task) in tasks {
                if await task.value { processed.append(value) }
            }
            await observable.flush()
            XCTAssertEqual(received.sorted(), processed.sorted())
            XCTAssertEqual(observable.boundedSubmissionCounts.admitted, 0)
            XCTAssertEqual(observable.boundedSubmissionCounts.waiting, 0)
        }
    }

    func testBoundedCancellationRacingPermitTransferReportsActualDelivery() async {
        for _ in 0..<20 {
            let observable = Observable<Int>(0, boundedCapacity: 1)
            let entered = expectation(description: "observer blocked")
            let release = DispatchSemaphore(value: 0)
            var received : [Int] = []
            await observable.addObserverAsync({ value in
                received.append(value)
                if value == 1 {
                    entered.fulfill()
                    XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
                }
            }, replayCurrentValue: false)
            let first = Task { await observable.updateBoundedAsync(1) }
            await fulfillment(of: [entered], timeout: 5)
            let waiting = Task { await observable.updateBoundedAsync(2) }
            var observedWaiter = false
            for _ in 0..<10_000 {
                if observable.boundedSubmissionCounts.waiting == 1 {
                    observedWaiter = true
                    break
                }
                await Task.yield()
            }
            XCTAssertTrue(observedWaiter)
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 { waiting.cancel() } else { release.signal() }
            }
            let firstResult = await first.value
            let secondResult = await waiting.value
            XCTAssertTrue(firstResult)
            await observable.flush()
            XCTAssertEqual(received.contains(2), secondResult)
            XCTAssertEqual(observable.boundedSubmissionCounts.admitted, 0)
        }
    }

    func testBoundedEventPumpDoesNotRetainObservable() async {
        weak var releasedObservable : Observable<Int>?
        do {
            let observable = Observable<Int>(0, boundedCapacity: 1)
            releasedObservable = observable
            let processed = await observable.updateBoundedAsync(1)
            XCTAssertTrue(processed)
        }
        for _ in 0..<10_000 where releasedObservable != nil {
            await Task.yield()
        }
        XCTAssertNil(releasedObservable)
    }

    // MARK: - PeerConnectionResponder

    func testResponderSynchronousListenerSkipsCurrentEventAndReceivesFutureEvent() async {
        let observable = Observable<PeerConnectionEvent>(.ready)
        let responder = PeerConnectionResponder(observer: observable)
        var receivedStarted = false

        responder.addListener({ event in
            if case .started = event {
                receivedStarted = true
            } else {
                XCTFail("Responder replayed the current event")
            }
        }, forKey: "listener")
        await observable.flush()
        XCTAssertFalse(receivedStarted)

        await observable.updateAsync(.started)

        XCTAssertTrue(receivedStarted)
    }

    func testResponderAsyncListenerSkipsCurrentEventAndReceivesFutureEvent() async {
        let observable = Observable<PeerConnectionEvent>(.ready)
        let responder = PeerConnectionResponder(observer: observable)
        var receivedStarted = false

        await responder.addListenerAsync({ event in
            if case .started = event {
                receivedStarted = true
            } else {
                XCTFail("Responder replayed the current event")
            }
        }, forKey: "listener")
        XCTAssertFalse(receivedStarted)

        await observable.updateAsync(.started)

        XCTAssertTrue(receivedStarted)
    }

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
