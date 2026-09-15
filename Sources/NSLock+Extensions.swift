//
//  NSLock+Extensions.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 8/23/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation

internal extension NSLock {

    func locked<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
