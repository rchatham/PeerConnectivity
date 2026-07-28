//
//  AsyncObservable.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 7/21/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation

@available(iOS 13.0, macOS 10.15, *)
internal actor AsyncObservable<T> {
    internal typealias Observer = (T) -> Void

    fileprivate var storedValue : T
    fileprivate var observers : [Observer] = []

    internal var value : T {
        return storedValue
    }

    internal init(_ v: T) {
        storedValue = v
    }

    internal func addObserver(_ observer: @escaping Observer) {
        let currentValue = storedValue
        observers.append(observer)
        observer(currentValue)
    }

    internal func removeAllObservers() {
        observers.removeAll()
    }

    internal func update(_ newValue: T) {
        storedValue = newValue
        let currentObservers = observers

        currentObservers.forEach { observer in
            observer(newValue)
        }
    }
}
