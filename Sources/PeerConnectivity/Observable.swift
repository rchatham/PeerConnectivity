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

    // MARK: - Properties -

    private let _value: Atomic<T>
    internal var value: T {
        set {
            _value.set(newValue)

            observers.forEach { observer in
                observer(newValue)
            }
        }
        get {
            _value.value
        }
    }

    internal var observers: [Observer] = []

    // MARK: - Initializers

    internal init(_ value: T) {
        _value = Atomic<T>(value: value)
    }

    // MARK: - Observers

    internal func addObserver(_ observer: @escaping Observer) {
        observer(value)
        observers.append(observer)
    }
}
