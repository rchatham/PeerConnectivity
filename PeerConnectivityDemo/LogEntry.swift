//
//  LogEntry.swift
//  PeerConnectivityDemo
//
//  Created by Reid Chatham on 9/15/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import Foundation

internal enum LogCategory : String, CaseIterable, Codable {
    case lifecycle = "Lifecycle"
    case peers = "Peers"
    case messages = "Messages"
    case errors = "Errors"
    case dataResources = "Data/Resources"
}

internal struct LogEntry : Codable {
    internal enum Direction : String, Codable {
        case inbound
        case outbound
        case local
    }

    internal let timestamp : Date
    internal let kind : String
    internal let detail : String
    internal let peerDisplayNames : [String]
    internal let direction : Direction

    internal init(timestamp: Date = Date(), kind: String, detail: String, peerDisplayNames: [String] = [], direction: Direction = .local) {
        self.timestamp = timestamp
        self.kind = kind
        self.detail = detail
        self.peerDisplayNames = peerDisplayNames
        self.direction = direction
    }
}

extension LogEntry {
    internal var category : LogCategory {
        if kind == "error" || kind.contains("error") || kind.contains("failed") {
            return .errors
        }
        if kind.hasPrefix("peer") || kind.hasPrefix("peers") || kind.hasPrefix("invitation") || kind.hasPrefix("certificate") {
            return .peers
        }
        if kind.hasPrefix("message") || kind.hasPrefix("legacy.event") {
            return .messages
        }
        if kind.hasPrefix("data") || kind.hasPrefix("resource") || kind.hasPrefix("stream") {
            return .dataResources
        }
        return .lifecycle
    }

    internal func textLine(dateFormatter: ISO8601DateFormatter) -> String {
        let peerSummary = peerDisplayNames.isEmpty ? "-" : peerDisplayNames.joined(separator: ", ")
        return "[\(dateFormatter.string(from: timestamp))] [\(direction.rawValue)] [\(category.rawValue)] \(kind): \(detail) (peers: \(peerSummary))"
    }
}
