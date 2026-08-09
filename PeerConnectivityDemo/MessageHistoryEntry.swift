//
//  MessageHistoryEntry.swift
//  PeerConnectivityDemo
//
//  Created by Reid Chatham on 9/15/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import Foundation

internal struct MessageHistoryEntry {
    internal enum Direction : String {
        case inbound = "Received"
        case outbound = "Sent"
    }

    internal let timestamp : Date
    internal let direction : Direction
    internal let sender : String
    internal let targets : [String]
    internal let text : String

    internal init(timestamp: Date = Date(), direction: Direction, sender: String, targets: [String], text: String) {
        self.timestamp = timestamp
        self.direction = direction
        self.sender = sender
        self.targets = targets
        self.text = text
    }

    internal func textLine(dateFormatter: DateFormatter) -> String {
        let targetSummary = targets.isEmpty ? "Broadcast" : targets.joined(separator: ", ")
        return "\(dateFormatter.string(from: timestamp)) · \(direction.rawValue) · \(sender) → \(targetSummary)\n\(text)"
    }
}
