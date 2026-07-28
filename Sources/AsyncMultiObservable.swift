//
//  AsyncMultiObservable.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 7/21/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation

@available(iOS 13.0, macOS 10.15, *)
internal actor AsyncMultiObservable<T> {
    internal typealias Observer = (T) -> Void

    fileprivate var storedValue : T
    fileprivate var observers : [String:Observer] = [:]

    internal var value : T {
        return storedValue
    }

    internal var observerCount : Int {
        return observers.count
    }

    internal init(_ v: T) {
        storedValue = v
    }

    internal func addObserver(_ observer: @escaping Observer, key: String) {
        let currentValue = storedValue
        observers[key] = observer
        observer(currentValue)
    }

    internal func removeObserverForkey(_ key: String) {
        observers.removeValue(forKey: key)
    }

    internal func removeAllObservers() {
        observers.removeAll()
    }

    internal func update(_ newValue: T) {
        storedValue = newValue
        let currentObservers = Array(observers.values)

        currentObservers.forEach { observer in
            observer(newValue)
        }
    }
}
