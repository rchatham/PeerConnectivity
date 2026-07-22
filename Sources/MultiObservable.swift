//
//  MultiObservable.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 1/18/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import Foundation

internal class MultiObservable<T> {
    internal typealias Observer = (T) -> Void

    fileprivate let lock = NSLock()
    fileprivate var storedValue : T
    fileprivate var storedObservers : [String:Observer] = [:]

    internal var observers : [String:Observer] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedObservers
        }
        set {
            lock.lock()
            storedObservers = newValue
            lock.unlock()
        }
    }

    internal func addObserver(_ observer: @escaping Observer, key: String) {
        let currentValue : T
        lock.lock()
        currentValue = storedValue
        storedObservers[key] = observer
        lock.unlock()

        observer(currentValue)
    }

    internal func removeObserverForkey(_ key: String) {
        lock.lock()
        storedObservers.removeValue(forKey: key)
        lock.unlock()
    }

    internal func removeAllObservers() {
        lock.lock()
        storedObservers.removeAll()
        lock.unlock()
    }

    internal var value : T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            let observers : [Observer]
            lock.lock()
            storedValue = newValue
            observers = Array(storedObservers.values)
            lock.unlock()

            observers.forEach { observer in
                observer(newValue)
            }
        }
    }

    internal init(_ v: T) {
        storedValue = v
    }
}
