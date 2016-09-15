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
    internal var observers: [String:Observer] = [:]
    
    internal func addObserver(_ observer: @escaping Observer, key: String) {
        observer(value)
        self.observers[key] = observer
    }
    
    internal func removeObserverForkey(_ key: String) {
        self.observers.removeValue(forKey: key)
    }
    
    internal var value: T {
        didSet {
            for (_, observer) in observers {
                observer(value)
            }
        }
    }
    
    internal init(_ v: T) {
        value = v
    }
}
