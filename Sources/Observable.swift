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
        Task { await addObserverAsync(observer, key: key) }
    }

    nonisolated internal func removeObserver(forKey key: String) {
        Task { await removeObserverAsync(forKey: key) }
    }

    nonisolated internal func removeAllObservers() {
        Task { await removeAllObserversAsync() }
    }

    nonisolated internal func update(_ newValue: T) {
        Task { await updateAsync(newValue) }
    }

    @discardableResult
    internal func addObserverAsync(_ observer: @escaping Observer) -> String {
        let key = UUID().uuidString
        addObserverAsync(observer, key: key)
        return key
    }

    internal func addObserverAsync(_ observer: @escaping Observer, key: String) {
        storeObserver(observer, key: key)
    }

    internal func removeObserverAsync(forKey key: String) {
        removeStoredObserver(forKey: key)
    }

    internal func removeAllObserversAsync() {
        removeStoredObservers()
    }

    internal func updateAsync(_ newValue: T) {
        setValue(newValue)
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
