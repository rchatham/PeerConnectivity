//
//  Observable.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/21/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

internal actor Observable<T> {
    internal typealias Observer = (T) -> Void
    fileprivate typealias Operation = () async -> Void

    internal private(set) var value : T {
        didSet {
            observers.values.forEach { observer in
                observer(value)
            }
        }
    }

    fileprivate var observers : [String:Observer] = [:]
    fileprivate let continuation : AsyncStream<Operation>.Continuation
    fileprivate var eventPump : Task<Void, Never>?

    internal var observerCount : Int {
        return observers.count
    }

    internal init(_ v: T) {
        value = v

        var operationContinuation : AsyncStream<Operation>.Continuation?
        let operations = AsyncStream<Operation> { continuation in
            operationContinuation = continuation
        }
        continuation = operationContinuation!

        eventPump = Task {
            for await operation in operations {
                await operation()
            }
        }
    }

    deinit {
        continuation.finish()
        eventPump?.cancel()
    }

    @discardableResult
    nonisolated internal func addObserver(_ observer: @escaping Observer) -> String {
        let key = UUID().uuidString
        addObserver(observer, key: key)
        return key
    }

    nonisolated internal func addObserver(_ observer: @escaping Observer, key: String) {
        continuation.yield { [weak self] in
            await self?.storeObserver(observer, key: key)
        }
    }

    nonisolated internal func removeObserver(forKey key: String) {
        continuation.yield { [weak self] in
            await self?.removeStoredObserver(forKey: key)
        }
    }

    nonisolated internal func removeAllObservers() {
        continuation.yield { [weak self] in
            await self?.removeStoredObservers()
        }
    }

    nonisolated internal func update(_ newValue: T) {
        continuation.yield { [weak self] in
            await self?.setValue(newValue)
        }
    }

    internal func flush() async {
        await withCheckedContinuation { continuation in
            self.continuation.yield {
                continuation.resume()
            }
        }
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
