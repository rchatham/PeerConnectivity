//
//  SyncObservableBridge.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 7/21/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation

@available(iOS 13.0, macOS 10.15, *)
internal enum SyncObservableBridge {
    /// Runs an async observable operation and blocks the current thread until it completes.
    ///
    /// Use this bridge only from synchronous delegate/GCD entry points that must preserve
    /// current in-line delivery semantics. Prefer `await` from async contexts. Do not call
    /// this from actor-isolated code or cooperative Swift-concurrency executors, because
    /// blocking those executors can deadlock or starve unrelated tasks.
    internal static func waitForAsync(_ operation: @escaping () async -> Void) {
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            await operation()
            semaphore.signal()
        }

        semaphore.wait()
    }

    internal static func addObserverAndWait<T>(_ observer: @escaping AsyncObservable<T>.Observer,
        to observable: AsyncObservable<T>) {
        waitForAsync {
            await observable.addObserver(observer)
        }
    }

    internal static func updateAndWait<T>(_ observable: AsyncObservable<T>, value: T) {
        waitForAsync {
            await observable.update(value)
        }
    }

    internal static func removeAllObserversAndWait<T>(from observable: AsyncObservable<T>) {
        waitForAsync {
            await observable.removeAllObservers()
        }
    }

    internal static func addObserverAndWait<T>(_ observer: @escaping AsyncMultiObservable<T>.Observer,
        to observable: AsyncMultiObservable<T>, key: String) {
        waitForAsync {
            await observable.addObserver(observer, key: key)
        }
    }

    internal static func updateAndWait<T>(_ observable: AsyncMultiObservable<T>, value: T) {
        waitForAsync {
            await observable.update(value)
        }
    }

    internal static func removeObserverAndWait<T>(forKey key: String, from observable: AsyncMultiObservable<T>) {
        waitForAsync {
            await observable.removeObserverForkey(key)
        }
    }

    internal static func removeAllObserversAndWait<T>(from observable: AsyncMultiObservable<T>) {
        waitForAsync {
            await observable.removeAllObservers()
        }
    }
}
