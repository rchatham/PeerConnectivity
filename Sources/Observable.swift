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

    internal private(set) var value : T {
        didSet {
            observers.values.forEach { observer in
                observer(value)
            }
        }
    }

    fileprivate var observers : [String:Observer] = [:]

    internal var observerCount : Int {
        return observers.count
    }

    internal init(_ v: T) {
        value = v
    }

    @discardableResult
    nonisolated internal func addObserver(_ observer: @escaping Observer) -> String {
        let key = UUID().uuidString
        addObserver(observer, key: key)
        return key
    }

    nonisolated internal func addObserver(_ observer: @escaping Observer, key: String) {
        Task { await storeObserver(observer, key: key) }
    }

    nonisolated internal func removeObserver(forKey key: String) {
        Task { await removeStoredObserver(forKey: key) }
    }

    nonisolated internal func removeAllObservers() {
        Task { await removeStoredObservers() }
    }

    nonisolated internal func update(_ newValue: T) {
        Task { await setValue(newValue) }
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
