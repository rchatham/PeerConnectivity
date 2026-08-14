//
//  Observable.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/21/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

fileprivate final class ObservableOperationQueue : @unchecked Sendable {
    fileprivate typealias Operation = () async -> Void

    private let lock = NSLock()
    private var tail = Task<Void, Never> {}

    @discardableResult
    fileprivate func submit(_ operation: @escaping Operation) -> Task<Void, Never> {
        lock.lock()
        let previous = tail
        let task = Task {
            await previous.value
            await operation()
        }
        tail = task
        lock.unlock()
        return task
    }
}

internal actor Observable<T> {
    internal typealias Observer = (T) -> Void

    internal private(set) var value : T {
        didSet {
            observers.values.forEach { observer in
                observer(value)
            }
        }
    }

    fileprivate var observers : [String:Observer] = [:]
    nonisolated fileprivate let operationQueue = ObservableOperationQueue()

    internal var observerCount : Int {
        return observers.count
    }

    internal init(_ v: T) {
        value = v
    }

    /// Schedules observer registration from synchronous callers.
    ///
    /// Synchronous submissions share a serialized task chain so observer lifecycle
    /// changes and updates are applied in call order without blocking the caller.
    @discardableResult
    nonisolated internal func addObserver(_ observer: @escaping Observer) -> String {
        let key = UUID().uuidString
        addObserver(observer, key: key)
        return key
    }

    nonisolated internal func addObserver(_ observer: @escaping Observer, key: String) {
        operationQueue.submit { [weak self] in
            await self?.storeObserver(observer, key: key)
        }
    }

    nonisolated internal func removeObserver(forKey key: String) {
        operationQueue.submit { [weak self] in
            await self?.removeStoredObserver(forKey: key)
        }
    }

    nonisolated internal func removeAllObservers() {
        operationQueue.submit { [weak self] in
            await self?.removeStoredObservers()
        }
    }

    nonisolated internal func update(_ newValue: T) {
        operationQueue.submit { [weak self] in
            await self?.setValue(newValue)
        }
    }

    @discardableResult
    nonisolated internal func addObserverAsync(_ observer: @escaping Observer) async -> String {
        let key = UUID().uuidString
        await addObserverAsync(observer, key: key)
        return key
    }

    nonisolated internal func addObserverAsync(_ observer: @escaping Observer, key: String) async {
        let task = operationQueue.submit { [weak self] in
            await self?.storeObserver(observer, key: key)
        }
        await task.value
    }

    nonisolated internal func removeObserverAsync(forKey key: String) async {
        let task = operationQueue.submit { [weak self] in
            await self?.removeStoredObserver(forKey: key)
        }
        await task.value
    }

    nonisolated internal func removeAllObserversAsync() async {
        let task = operationQueue.submit { [weak self] in
            await self?.removeStoredObservers()
        }
        await task.value
    }

    nonisolated internal func updateAsync(_ newValue: T) async {
        let task = operationQueue.submit { [weak self] in
            await self?.setValue(newValue)
        }
        await task.value
    }

    nonisolated internal func flush() async {
        let task = operationQueue.submit {}
        await task.value
    }

    fileprivate func storeObserver(_ observer: @escaping Observer, key: String) {
        observers[key] = observer
        observer(value)
    }

    fileprivate func removeStoredObserver(forKey key: String) {
        observers.removeValue(forKey: key)
    }

    fileprivate func removeStoredObservers() {
        observers.removeAll()
    }

    fileprivate func setValue(_ newValue: T) {
        value = newValue
    }
}
