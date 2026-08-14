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

    fileprivate enum Operation {
        case addObserver(Observer, key: String, replayCurrentValue: Bool, completion: CheckedContinuation<Void, Never>?)
        case removeObserver(key: String, completion: CheckedContinuation<Void, Never>?)
        case removeAllObservers(completion: CheckedContinuation<Void, Never>?)
        case update(T, completion: CheckedContinuation<Void, Never>?)
        case barrier(CheckedContinuation<Void, Never>)
    }

    internal private(set) var value : T {
        didSet {
            observers.values.forEach { observer in
                observer(value)
            }
        }
    }

    fileprivate var observers : [String:Observer] = [:]
    nonisolated fileprivate let operationContinuation : AsyncStream<Operation>.Continuation
    nonisolated(unsafe) fileprivate var eventPump : Task<Void, Never>?

    internal var observerCount : Int {
        return observers.count
    }

    internal init(_ v: T) {
        let (operations, continuation) = AsyncStream.makeStream(of: Operation.self)

        value = v
        operationContinuation = continuation
        eventPump = nil
        eventPump = Task { [weak self] in
            for await operation in operations {
                guard let self = self else { break }
                await self.perform(operation)
            }
        }
    }

    deinit {
        operationContinuation.finish()
        eventPump?.cancel()
    }

    /// Schedules observer registration from synchronous callers.
    ///
    /// Synchronous submissions enter the actor's operation stream so observer
    /// lifecycle changes and updates are applied in call order without blocking.
    @discardableResult
    nonisolated internal func addObserver(
        _ observer: @escaping Observer,
        replayCurrentValue: Bool = true
    ) -> String {
        let key = UUID().uuidString
        addObserver(observer, key: key, replayCurrentValue: replayCurrentValue)
        return key
    }

    nonisolated internal func addObserver(
        _ observer: @escaping Observer,
        key: String,
        replayCurrentValue: Bool = true
    ) {
        operationContinuation.yield(.addObserver(
            observer,
            key: key,
            replayCurrentValue: replayCurrentValue,
            completion: nil
        ))
    }

    nonisolated internal func removeObserver(forKey key: String) {
        operationContinuation.yield(.removeObserver(key: key, completion: nil))
    }

    nonisolated internal func removeAllObservers() {
        operationContinuation.yield(.removeAllObservers(completion: nil))
    }

    nonisolated internal func update(_ newValue: T) {
        operationContinuation.yield(.update(newValue, completion: nil))
    }

    @discardableResult
    nonisolated internal func addObserverAsync(
        _ observer: @escaping Observer,
        replayCurrentValue: Bool = true
    ) async -> String {
        let key = UUID().uuidString
        await addObserverAsync(observer, key: key, replayCurrentValue: replayCurrentValue)
        return key
    }

    nonisolated internal func addObserverAsync(
        _ observer: @escaping Observer,
        key: String,
        replayCurrentValue: Bool = true
    ) async {
        await enqueueAndWait { completion in
            .addObserver(
                observer,
                key: key,
                replayCurrentValue: replayCurrentValue,
                completion: completion
            )
        }
    }

    nonisolated internal func removeObserverAsync(forKey key: String) async {
        await enqueueAndWait { completion in
            .removeObserver(key: key, completion: completion)
        }
    }

    nonisolated internal func removeAllObserversAsync() async {
        await enqueueAndWait { completion in
            .removeAllObservers(completion: completion)
        }
    }

    nonisolated internal func updateAsync(_ newValue: T) async {
        await enqueueAndWait { completion in
            .update(newValue, completion: completion)
        }
    }

    nonisolated internal func flush() async {
        await enqueueAndWait { completion in
            .barrier(completion)
        }
    }

    nonisolated fileprivate func enqueueAndWait(
        _ makeOperation: (CheckedContinuation<Void, Never>) -> Operation
    ) async {
        await withCheckedContinuation { completion in
            switch operationContinuation.yield(makeOperation(completion)) {
            case .enqueued:
                break
            case .dropped, .terminated:
                completion.resume()
            @unknown default:
                completion.resume()
            }
        }
    }

    fileprivate func perform(_ operation: Operation) {
        switch operation {
        case let .addObserver(observer, key, replayCurrentValue, completion):
            storeObserver(observer, key: key, replayCurrentValue: replayCurrentValue)
            completion?.resume()
        case let .removeObserver(key, completion):
            removeStoredObserver(forKey: key)
            completion?.resume()
        case let .removeAllObservers(completion):
            removeStoredObservers()
            completion?.resume()
        case let .update(newValue, completion):
            setValue(newValue)
            completion?.resume()
        case let .barrier(completion):
            completion.resume()
        }
    }

    fileprivate func storeObserver(
        _ observer: @escaping Observer,
        key: String,
        replayCurrentValue: Bool
    ) {
        observers[key] = observer
        if replayCurrentValue {
            observer(value)
        }
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
