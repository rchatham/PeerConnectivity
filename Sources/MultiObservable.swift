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

    // MARK: - Properties

    internal var observers: [String:Observer] = [:]
    
    private let _value: Atomic<T>
    internal var value: T {
        set {
            _value.set(newValue)
            logger.info("Manager PeerConnectionEvent - \(newValue)")

            for (_, observer) in observers {
                observer(newValue)
            }
        }
        get {
            return _value.value
        }
    }

    // MAKRK: - Initializers -

    internal init(_ value: T) {
        _value = Atomic<T>(value: value)
    }

    // MARK: - Observers

    internal func addObserver(_ observer: @escaping Observer, key: String) {
        observer(value)
        self.observers[key] = observer
    }

    internal func removeObserverForkey(_ key: String) {
        self.observers.removeValue(forKey: key)
    }

}
