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

    func testObservableCanSkipCurrentValueAndReceiveFutureUpdates() async throws {
        let observable = Observable<Int>(7)
        var received : [Int] = []

        await observable.addObserverAsync({ value in
            received.append(value)
        }, replayCurrentValue: false)
        XCTAssertTrue(received.isEmpty)

        await observable.updateAsync(8)

        XCTAssertEqual(received, [8])
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

    func testObservableAsyncOperationsCompleteAfterActorMutation() async {
        let observable = Observable<Int>(0)
        var received : [Int] = []

        let generatedKey = await observable.addObserverAsync { received.append($0) }
        var observerCount = await observable.observerCount
        XCTAssertEqual(observerCount, 1)
        XCTAssertEqual(received, [0])

        await observable.updateAsync(1)
        let value = await observable.value
        XCTAssertEqual(value, 1)
        XCTAssertEqual(received, [0, 1])

        await observable.addObserverAsync({ _ in }, key: "keyed")
        observerCount = await observable.observerCount
        XCTAssertEqual(observerCount, 2)

        await observable.removeObserverAsync(forKey: generatedKey)
        observerCount = await observable.observerCount
        XCTAssertEqual(observerCount, 1)

        await observable.removeAllObserversAsync()
        observerCount = await observable.observerCount
        XCTAssertEqual(observerCount, 0)
    }

    func testObservableEventPumpDoesNotRetainObservable() async {
        weak var releasedObservable : Observable<Int>?

        do {
            let observable = Observable<Int>(0)
            releasedObservable = observable
            await observable.flush()
        }

        for _ in 0..<10 where releasedObservable != nil {
            await Task.yield()
        }

        XCTAssertNil(releasedObservable)
    }

    func testObservableAsyncOperationWaitsForEarlierSynchronousOperations() async {
        let observable = Observable<Int>(0)
        var received : [Int] = []

        observable.addObserver({ received.append($0) }, key: "listener")
        observable.update(1)
        await observable.updateAsync(2)

        XCTAssertEqual(received, [0, 1, 2])

        observable.removeObserver(forKey: "listener")
        await observable.updateAsync(3)

        let value = await observable.value
        XCTAssertEqual(received, [0, 1, 2])
        XCTAssertEqual(value, 3)
    }

    func testObservableSynchronousLifecycleAndUpdatesRemainFIFO() async {
        let observable = Observable<Int>(0)
        var received : [Int] = []

        for value in 1...100 {
            let key = "listener-\(value)"
            observable.addObserver({ received.append($0) }, key: key)
            observable.update(value)
            observable.removeObserver(forKey: key)
        }
        await observable.flush()

        XCTAssertEqual(received, Array(0...99).flatMap { [$0, $0 + 1] })
    }

    func testObservableSynchronousAddThenUpdateRemainsFIFO() async {
        let observable = Observable<Int>(0)
        var received : [Int] = []

        observable.addObserver({ received.append($0) }, key: "listener")
        for value in 1...100 {
            observable.update(value)
        }
        await observable.flush()

        XCTAssertEqual(received, Array(0...100))
    }

    func testObservableSynchronousRemoveThenUpdateRemainsFIFO() async {
        let observable = Observable<Int>(0)
        var received : [Int] = []

        await observable.addObserverAsync({ received.append($0) }, key: "listener")
        observable.removeObserver(forKey: "listener")
        for value in 1...100 {
            observable.update(value)
        }
        await observable.flush()

        let finalValue = await observable.value
        XCTAssertEqual(received, [0])
        XCTAssertEqual(finalValue, 100)
    }

    func testBoundedUpdateWaitsForCapacityAndPreservesMixedFIFO() async {
        let observable = Observable<Int>(0, boundedCapacity: 1)
        let entered = expectation(description: "bounded observer blocked")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var received : [Int] = []
        await observable.addObserverAsync({ value in
            received.append(value)
            if value == 2 {
                entered.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
        }, replayCurrentValue: false)

        observable.update(1)
        let first = Task { await observable.updateBoundedAsync(2) }
        await fulfillment(of: [entered], timeout: 5) // Value 2 is processing, not merely reserved.
        observable.update(3)
        let second = Task { await observable.updateBoundedAsync(4) }
        let secondWaiting = await awaitBoundedCounts(observable, admitted: 1, waiting: 1)
        XCTAssertTrue(secondWaiting)
        XCTAssertEqual(observable.boundedSubmissionCounts.admitted, 1)

        release.signal()
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertTrue(firstResult)
        XCTAssertTrue(secondResult)
        await observable.flush()
        XCTAssertEqual(received, [1, 2, 3, 4])
        XCTAssertEqual(observable.boundedSubmissionCounts.admitted, 0)
    }

    func testBoundedCancellationWhileWaitingDoesNotSubmitOrLeakPermit() async {
        let observable = Observable<Int>(0, boundedCapacity: 1)
        let entered = expectation(description: "observer blocked")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var received : [Int] = []
        await observable.addObserverAsync({ value in
            received.append(value)
            if value == 2 {
                entered.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
        }, replayCurrentValue: false)
        observable.update(1)
        let accepted = Task { await observable.updateBoundedAsync(2) }
        await fulfillment(of: [entered], timeout: 5)
        let cancelled = Task { await observable.updateBoundedAsync(3) }
        let cancelledWaiting = await awaitBoundedCounts(observable, admitted: 1, waiting: 1)
        XCTAssertTrue(cancelledWaiting)
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        XCTAssertFalse(cancelledResult)
        XCTAssertEqual(observable.boundedSubmissionCounts.waiting, 0)
        let next = Task { await observable.updateBoundedAsync(4) }
        let nextWaiting = await awaitBoundedCounts(observable, admitted: 1, waiting: 1)
        XCTAssertTrue(nextWaiting)

        release.signal()
        let acceptedResult = await accepted.value
        let nextResult = await next.value
        XCTAssertTrue(acceptedResult)
        XCTAssertTrue(nextResult)
        XCTAssertEqual(received, [1, 2, 4])
        XCTAssertEqual(observable.boundedSubmissionCounts.admitted, 0)
    }

    func testFinishRejectsReservedUpdateBeforeStreamTermination() async {
        let reserved = expectation(description: "permit reserved before enqueue")
        let gateClosed = expectation(description: "admission closed before stream finish")
        let releaseEnqueue = DispatchSemaphore(value: 0)
        let releaseFinish = DispatchSemaphore(value: 0)
        defer {
            releaseEnqueue.signal()
            releaseFinish.signal()
        }
        let observable = Observable<Int>(0, boundedCapacity: 1, beforeBoundedEnqueue: {
            reserved.fulfill()
            XCTAssertEqual(releaseEnqueue.wait(timeout: .now() + 5), .success)
        }, afterBoundedClose: {
            gateClosed.fulfill()
            XCTAssertEqual(releaseFinish.wait(timeout: .now() + 5), .success)
        })
        var received : [Int] = []
        await observable.addObserverAsync({ received.append($0) }, replayCurrentValue: false)

        let submission = Task { await observable.updateBoundedAsync(1) }
        await fulfillment(of: [reserved], timeout: 5)
        XCTAssertEqual(observable.boundedSubmissionCounts.admitted, 1)
        let closing = Task { observable.finish() }
        await fulfillment(of: [gateClosed], timeout: 5)

        // The stream is still open: a yield without the shared admission lock would succeed.
        releaseEnqueue.signal()
        let processed = await submission.value
        XCTAssertFalse(processed)
        XCTAssertEqual(observable.boundedSubmissionCounts.admitted, 0)
        releaseFinish.signal()
        await closing.value
        await observable.finishAndWait()
        let value = await observable.value
        XCTAssertEqual(value, 0)
        XCTAssertTrue(received.isEmpty)
    }

    func testFinishAndWaitDrainsBufferedOperationsWhileFlushAfterFinishIsNotABarrier() async {
        let observable = Observable<Int>(0)
        let entered = expectation(description: "observer blocked")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var received : [Int] = []
        await observable.addObserverAsync({ value in
            received.append(value)
            if value == 1 {
                entered.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
        }, replayCurrentValue: false)
        observable.update(1)
        await fulfillment(of: [entered], timeout: 5)
        observable.update(2)
        observable.finish()

        let drained = DispatchSemaphore(value: 0)
        let drain = Task {
            await observable.finishAndWait()
            drained.signal()
        }
        let flushed = DispatchSemaphore(value: 0)
        let flush = Task {
            await observable.flush()
            flushed.signal()
        }
        XCTAssertEqual(flushed.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(drained.wait(timeout: .now() + 0.05), .timedOut)
        release.signal()
        await drain.value
        await flush.value
        XCTAssertEqual(received, [1, 2])
    }

    func testFinishAndWaitClosesAnOpenStream() async {
        let observable = Observable<Int>(0)
        observable.update(1)
        await observable.finishAndWait()
        let value = await observable.value
        let rejected = await observable.updateBoundedAsync(2)
        XCTAssertEqual(value, 1)
        XCTAssertFalse(rejected)
        await observable.finishAndWait() // Repeated shutdown is safe.
    }

    func testBoundedFinishRejectsWaitersAndDrainsAcceptedUpdate() async {
        let observable = Observable<Int>(0, boundedCapacity: 1)
        let entered = expectation(description: "observer blocked")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var received : [Int] = []
        await observable.addObserverAsync({ value in
            received.append(value)
            if value == 2 {
                entered.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
        }, replayCurrentValue: false)
        observable.update(1)
        let accepted = Task { await observable.updateBoundedAsync(2) }
        await fulfillment(of: [entered], timeout: 5)
        let waiting = Task { await observable.updateBoundedAsync(3) }
        let secondWaiting = await awaitBoundedCounts(observable, admitted: 1, waiting: 1)
        XCTAssertTrue(secondWaiting)
        observable.finish()
        let waitingResult = await waiting.value
        let rejectedResult = await observable.updateBoundedAsync(4)
        XCTAssertFalse(waitingResult)
        XCTAssertFalse(rejectedResult)
        let drain = Task { await observable.finishAndWait() }
        release.signal()
        await drain.value
        let acceptedResult = await accepted.value
        XCTAssertTrue(acceptedResult)
        XCTAssertEqual(received, [1, 2])
        XCTAssertEqual(observable.boundedSubmissionCounts.admitted, 0)
    }

    /// Yields until the permit state reaches an expected value; never relies on a sleep duration.
    private func awaitBoundedCounts(_ observable: Observable<Int>, admitted: Int, waiting: Int) async -> Bool {
        for _ in 0..<10_000 {
            let counts = observable.boundedSubmissionCounts
            if counts.admitted == admitted && counts.waiting == waiting { return true }
            await Task.yield()
        }
        return false
    }
}
