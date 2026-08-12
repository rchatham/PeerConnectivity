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

    fileprivate enum Command {
        case addObserver(observer: Observer, key: String)
        case removeObserver(key: String)
        case removeAllObservers
        case update(T)
    }

    fileprivate var storedValue : T
    fileprivate var observers : [String:Observer] = [:]
    fileprivate let continuation : AsyncStream<Command>.Continuation
    fileprivate var eventPump : Task<Void, Never>?

    internal var value : T {
        return storedValue
    }

    internal var observerCount : Int {
        return observers.count
    }

    internal init(_ v: T) {
        storedValue = v

        var commandContinuation : AsyncStream<Command>.Continuation?
        let commandStream = AsyncStream<Command> { continuation in
            commandContinuation = continuation
        }
        continuation = commandContinuation!

        eventPump = Task { [weak self] in
            for await command in commandStream {
                await self?.perform(command)
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
        continuation.yield(.addObserver(observer: observer, key: key))
    }

    nonisolated internal func removeObserver(forKey key: String) {
        continuation.yield(.removeObserver(key: key))
    }

    nonisolated internal func removeAllObservers() {
        continuation.yield(.removeAllObservers)
    }

    nonisolated internal func update(_ newValue: T) {
        continuation.yield(.update(newValue))
    }

    fileprivate func perform(_ command: Command) {
        switch command {
        case .addObserver(let observer, let key):
            observers[key] = observer
            observer(storedValue)
        case .removeObserver(let key):
            observers.removeValue(forKey: key)
        case .removeAllObservers:
            observers.removeAll()
        case .update(let newValue):
            storedValue = newValue
            let currentObservers = Array(observers.values)

            currentObservers.forEach { observer in
                observer(newValue)
            }
        }
    }
}
