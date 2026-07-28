//
//  AsyncObservableTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 7/21/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
@testable import PeerConnectivity

@available(iOS 13.0, macOS 10.15, *)
final class AsyncObservableTests: XCTestCase {

    // MARK: - AsyncObservable

    func testAsyncObservableReplaysCurrentValueWhenObserverIsAdded() async {
        let observable = AsyncObservable<Int>(42)
        let lock = NSLock()
        var deliveredValues : [Int] = []

        await observable.addObserver { value in
            lock.lock()
            deliveredValues.append(value)
            lock.unlock()
        }

        XCTAssertEqual(deliveredValues, [42])
    }

    func testAsyncObservableDeliversUpdatesInRegistrationOrder() async {
        let observable = AsyncObservable<Int>(0)
        let lock = NSLock()
        var deliveredValues : [String] = []

        await observable.addObserver { value in
            lock.lock()
            deliveredValues.append("first-\(value)")
            lock.unlock()
        }
        await observable.addObserver { value in
            lock.lock()
            deliveredValues.append("second-\(value)")
            lock.unlock()
        }
        await observable.update(1)

        let currentValue = await observable.value
        XCTAssertEqual(deliveredValues, ["first-0", "second-0", "first-1", "second-1"])
        XCTAssertEqual(currentValue, 1)
    }

    func testAsyncObservableHandlesConcurrentUpdates() async {
        let observable = AsyncObservable<Int>(0)
        let lock = NSLock()
        var deliveryCount = 0

        await observable.addObserver { _ in
            lock.lock()
            deliveryCount += 1
            lock.unlock()
        }

        await withTaskGroup(of: Void.self) { group in
            for index in 1...100 {
                group.addTask {
                    await observable.update(index)
                }
            }
        }

        XCTAssertGreaterThanOrEqual(deliveryCount, 101)
    }

    // MARK: - AsyncMultiObservable

    func testAsyncMultiObservableCanRemoveObserverDuringDelivery() async {
        let observable = AsyncMultiObservable<Int>(0)
        let lock = NSLock()
        var deliveredValues : [Int] = []

        await observable.addObserver({ value in
            lock.lock()
            deliveredValues.append(value)
            lock.unlock()
            Task {
                await observable.removeObserverForkey("self-removing")
            }
        }, key: "self-removing")

        await observable.update(1)
        await waitForAsyncRemoval(from: observable)
        let observerCount = await observable.observerCount
        await observable.update(2)

        XCTAssertEqual(observerCount, 0)
        XCTAssertEqual(deliveredValues, [0, 1])
    }

    private func waitForAsyncRemoval(from observable: AsyncMultiObservable<Int>) async {
        for _ in 0..<10 {
            if await observable.observerCount == 0 { return }
            await Task.yield()
        }
    }

    // MARK: - SyncObservableBridge

    func testSyncObservableBridgeWaitsForAsyncObservableDelivery() {
        let observable = AsyncObservable<Int>(0)
        let queue = DispatchQueue(label: "PeerConnectivity.AsyncObservableTests.syncBridge")
        let completed = expectation(description: "sync bridge completed")
        let lock = NSLock()
        var deliveredValues : [Int] = []

        queue.async {
            SyncObservableBridge.addObserverAndWait({ value in
                lock.lock()
                deliveredValues.append(value)
                lock.unlock()
            }, to: observable)
            SyncObservableBridge.updateAndWait(observable, value: 1)

            lock.lock()
            let values = deliveredValues
            lock.unlock()

            XCTAssertEqual(values, [0, 1])
            completed.fulfill()
        }

        wait(for: [completed], timeout: 5)
    }

    func testSyncObservableBridgeWaitsForAsyncMultiObservableDelivery() {
        let observable = AsyncMultiObservable<Int>(0)
        let queue = DispatchQueue(label: "PeerConnectivity.AsyncObservableTests.syncMultiBridge")
        let completed = expectation(description: "sync multi bridge completed")
        let lock = NSLock()
        var deliveredValues : [Int] = []

        queue.async {
            SyncObservableBridge.addObserverAndWait({ value in
                lock.lock()
                deliveredValues.append(value)
                lock.unlock()
            }, to: observable, key: "listener")
            SyncObservableBridge.updateAndWait(observable, value: 1)
            SyncObservableBridge.removeObserverAndWait(forKey: "listener", from: observable)
            SyncObservableBridge.updateAndWait(observable, value: 2)

            lock.lock()
            let values = deliveredValues
            lock.unlock()

            XCTAssertEqual(values, [0, 1])
            completed.fulfill()
        }

        wait(for: [completed], timeout: 5)
    }
}
