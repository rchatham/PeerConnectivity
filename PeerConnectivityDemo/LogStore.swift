//
//  LogStore.swift
//  PeerConnectivityDemo
//
//  Created by Reid Chatham on 9/15/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import Foundation

internal final class LogStore {
    internal private(set) var entries : [LogEntry] = []

    private let encoder : JSONEncoder
    private let compactEncoder : JSONEncoder
    private let dateFormatter : ISO8601DateFormatter

    internal init() {
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        compactEncoder = JSONEncoder()
        compactEncoder.outputFormatting = [.sortedKeys]
        compactEncoder.dateEncodingStrategy = .iso8601
    }

    internal func append(_ entry: LogEntry) {
        entries.append(entry)
    }

    internal func clear() {
        entries.removeAll()
    }

    internal func textSummary(categories: Set<LogCategory> = Set(LogCategory.allCases)) -> String {
        let filteredEntries = entries.filter { categories.contains($0.category) }
        guard !filteredEntries.isEmpty else { return "No PeerConnectivity demo events recorded for the selected filters." }
        return filteredEntries.map { $0.textLine(dateFormatter: dateFormatter) }.joined(separator: "\n")
    }

    internal func jsonExport() -> String {
        guard let data = try? encoder.encode(entries),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    internal func jsonLinesExport() -> String {
        return entries.compactMap { entry in
            guard let data = try? compactEncoder.encode(entry) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")
    }

    internal func shareText() -> String {
        return """
        PeerConnectivity Demo Log
        =========================

        Summary
        -------
        \(textSummary())

        JSON
        ----
        \(jsonExport())

        JSON Lines
        ----------
        \(jsonLinesExport())
        """
    }
}
