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
    internal var observers: [Observer] = []
  
    internal func addObserver(_ observer: @escaping Observer) {
        observer(value)
        self.observers.append(observer)
    }
  
    internal var value: T {
        didSet {
            observers.forEach { observer in
                observer(value)
            }
        }
    }
  
    internal init(_ v: T) {
        value = v
    }
}
