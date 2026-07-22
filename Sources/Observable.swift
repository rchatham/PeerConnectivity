//
//  Observable.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/21/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//
//  Based on Jake Lin's Observable class from SwiftWeather
//

import Foundation

internal class Observable<T> {
    internal typealias Observer = (T) -> Void

    fileprivate let lock = NSLock()
    fileprivate var storedValue : T
    fileprivate var storedObservers : [Observer] = []

    internal var observers : [Observer] {
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

    internal func addObserver(_ observer: @escaping Observer) {
        let currentValue : T
        lock.lock()
        currentValue = storedValue
        storedObservers.append(observer)
        lock.unlock()

        observer(currentValue)
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
            observers = storedObservers
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
