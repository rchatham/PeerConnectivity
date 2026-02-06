//
//  PeerMessageTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 2/2/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
@testable import PeerConnectivity

// MARK: - Test Message Types

/// Simple message for basic tests
struct SimpleMessage: PeerMessage {
    let text: String
}

/// Message with custom messageType
struct CustomTypeMessage: PeerMessage {
    static var messageType: String { "custom-type-v1" }
    let value: Int
}

/// Complex message with various field types
struct ComplexMessage: PeerMessage {
    let id: UUID
    let timestamp: Date
    let count: Int
    let isActive: Bool
    let tags: [String]
    let metadata: [String: String]?
}

/// Message with empty/optional fields
struct OptionalFieldsMessage: PeerMessage {
    let required: String
    let optional: String?
    let optionalInt: Int?
}

/// Message with nested types
struct NestedMessage: PeerMessage {
    struct Inner: Codable, Equatable {
        let name: String
        let value: Double
    }
    let outer: String
    let inner: Inner
}

// MARK: - PeerMessageTests

class PeerMessageTests: XCTestCase {

    // MARK: - Helper Methods

    /// Encodes a message using the same logic as sendMessage
    private func encodeMessage<T: PeerMessage>(_ message: T) throws -> Data {
        var envelope: [String: Data] = [:]
        envelope["type"] = T.messageType.data(using: .utf8)
        envelope["payload"] = try JSONEncoder().encode(message)
        return try JSONEncoder().encode(envelope)
    }

    /// Decodes an envelope and extracts the messageType and payload
    private func decodeEnvelope(_ data: Data) throws -> (messageType: String, payload: Data) {
        let envelope = try JSONDecoder().decode([String: Data].self, from: data)
        guard let typeData = envelope["type"],
              let messageType = String(data: typeData, encoding: .utf8),
              let payload = envelope["payload"] else {
            throw NSError(domain: "PeerMessageTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid envelope structure"])
        }
        return (messageType, payload)
    }

    // MARK: - PeerMessage Protocol Tests

    func testDefaultMessageType() {
        // Default messageType should use the type name
        XCTAssertEqual(SimpleMessage.messageType, "SimpleMessage")
        XCTAssertEqual(ComplexMessage.messageType, "ComplexMessage")
        XCTAssertEqual(OptionalFieldsMessage.messageType, "OptionalFieldsMessage")
        XCTAssertEqual(NestedMessage.messageType, "NestedMessage")
    }

    func testCustomMessageType() {
        // Custom messageType should override the default
        XCTAssertEqual(CustomTypeMessage.messageType, "custom-type-v1")
    }

    func testCodableConformance() throws {
        // Verify encode/decode round-trip for simple message
        let original = SimpleMessage(text: "Hello, World!")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SimpleMessage.self, from: encoded)

        XCTAssertEqual(original.text, decoded.text)
    }

    // MARK: - Message Encoding Tests

    func testEnvelopeStructure() throws {
        // Verify JSON envelope has "type" and "payload" keys
        let message = SimpleMessage(text: "Test")
        let data = try encodeMessage(message)

        let envelope = try JSONDecoder().decode([String: Data].self, from: data)
        XCTAssertNotNil(envelope["type"], "Envelope should have 'type' key")
        XCTAssertNotNil(envelope["payload"], "Envelope should have 'payload' key")
        XCTAssertEqual(envelope.count, 2, "Envelope should only have 'type' and 'payload' keys")
    }

    func testTypeFieldEncoding() throws {
        // Verify messageType is correctly UTF-8 encoded
        let message = SimpleMessage(text: "Test")
        let data = try encodeMessage(message)

        let (messageType, _) = try decodeEnvelope(data)
        XCTAssertEqual(messageType, "SimpleMessage")
    }

    func testCustomTypeFieldEncoding() throws {
        // Verify custom messageType is correctly encoded
        let message = CustomTypeMessage(value: 42)
        let data = try encodeMessage(message)

        let (messageType, _) = try decodeEnvelope(data)
        XCTAssertEqual(messageType, "custom-type-v1")
    }

    func testPayloadEncoding() throws {
        // Verify message payload is valid JSON
        let message = SimpleMessage(text: "Payload Test")
        let data = try encodeMessage(message)

        let (_, payload) = try decodeEnvelope(data)

        // Payload should decode back to the original message
        let decoded = try JSONDecoder().decode(SimpleMessage.self, from: payload)
        XCTAssertEqual(decoded.text, message.text)
    }

    // MARK: - Message Decoding Tests

    func testEnvelopeDecoding() throws {
        // Verify JSON envelope can be decoded
        let message = SimpleMessage(text: "Decode Test")
        let data = try encodeMessage(message)

        // Should not throw
        _ = try JSONDecoder().decode([String: Data].self, from: data)
    }

    func testMessageTypeExtraction() throws {
        // Verify messageType is correctly extracted from envelope
        let simpleMessage = SimpleMessage(text: "Extract Test")
        let simpleData = try encodeMessage(simpleMessage)
        let (simpleType, _) = try decodeEnvelope(simpleData)
        XCTAssertEqual(simpleType, "SimpleMessage")

        let customMessage = CustomTypeMessage(value: 100)
        let customData = try encodeMessage(customMessage)
        let (customType, _) = try decodeEnvelope(customData)
        XCTAssertEqual(customType, "custom-type-v1")
    }

    func testPayloadDecoding() throws {
        // Verify payload decodes to correct type
        let original = ComplexMessage(
            id: UUID(),
            timestamp: Date(),
            count: 42,
            isActive: true,
            tags: ["swift", "networking"],
            metadata: ["key": "value"]
        )

        let data = try encodeMessage(original)
        let (messageType, payload) = try decodeEnvelope(data)

        XCTAssertEqual(messageType, "ComplexMessage")

        let decoded = try JSONDecoder().decode(ComplexMessage.self, from: payload)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.count, original.count)
        XCTAssertEqual(decoded.isActive, original.isActive)
        XCTAssertEqual(decoded.tags, original.tags)
        XCTAssertEqual(decoded.metadata, original.metadata)
    }

    // MARK: - Round-Trip Tests

    func testSimpleMessageRoundTrip() throws {
        // Encode then decode simple message
        let original = SimpleMessage(text: "Round Trip")
        let data = try encodeMessage(original)
        let (messageType, payload) = try decodeEnvelope(data)
        let decoded = try JSONDecoder().decode(SimpleMessage.self, from: payload)

        XCTAssertEqual(messageType, SimpleMessage.messageType)
        XCTAssertEqual(decoded.text, original.text)
    }

    func testComplexMessageRoundTrip() throws {
        // Message with Date, nested types, optionals
        let uuid = UUID()
        let date = Date()
        let original = ComplexMessage(
            id: uuid,
            timestamp: date,
            count: 999,
            isActive: false,
            tags: ["tag1", "tag2", "tag3"],
            metadata: ["author": "test", "version": "1.0"]
        )

        let data = try encodeMessage(original)
        let (messageType, payload) = try decodeEnvelope(data)
        let decoded = try JSONDecoder().decode(ComplexMessage.self, from: payload)

        XCTAssertEqual(messageType, "ComplexMessage")
        XCTAssertEqual(decoded.id, uuid)
        XCTAssertEqual(decoded.count, 999)
        XCTAssertEqual(decoded.isActive, false)
        XCTAssertEqual(decoded.tags.count, 3)
        XCTAssertEqual(decoded.metadata?["author"], "test")
    }

    func testNestedMessageRoundTrip() throws {
        // Message with nested struct
        let inner = NestedMessage.Inner(name: "inner", value: 3.14159)
        let original = NestedMessage(outer: "outer", inner: inner)

        let data = try encodeMessage(original)
        let (messageType, payload) = try decodeEnvelope(data)
        let decoded = try JSONDecoder().decode(NestedMessage.self, from: payload)

        XCTAssertEqual(messageType, "NestedMessage")
        XCTAssertEqual(decoded.outer, original.outer)
        XCTAssertEqual(decoded.inner, original.inner)
    }

    func testMultipleMessageTypes() throws {
        // Different message types have distinct messageTypes
        let simple = SimpleMessage(text: "Simple")
        let custom = CustomTypeMessage(value: 42)
        let complex = ComplexMessage(
            id: UUID(),
            timestamp: Date(),
            count: 1,
            isActive: true,
            tags: [],
            metadata: nil
        )

        let simpleData = try encodeMessage(simple)
        let customData = try encodeMessage(custom)
        let complexData = try encodeMessage(complex)

        let (simpleType, _) = try decodeEnvelope(simpleData)
        let (customType, _) = try decodeEnvelope(customData)
        let (complexType, _) = try decodeEnvelope(complexData)

        XCTAssertEqual(simpleType, "SimpleMessage")
        XCTAssertEqual(customType, "custom-type-v1")
        XCTAssertEqual(complexType, "ComplexMessage")

        // All should be distinct
        XCTAssertNotEqual(simpleType, customType)
        XCTAssertNotEqual(simpleType, complexType)
        XCTAssertNotEqual(customType, complexType)
    }

    // MARK: - Edge Cases

    func testEmptyStringFields() throws {
        // Message with empty strings
        let original = SimpleMessage(text: "")
        let data = try encodeMessage(original)
        let (_, payload) = try decodeEnvelope(data)
        let decoded = try JSONDecoder().decode(SimpleMessage.self, from: payload)

        XCTAssertEqual(decoded.text, "")
    }

    func testOptionalFieldsWithNil() throws {
        // Message with nil optionals
        let original = OptionalFieldsMessage(
            required: "required value",
            optional: nil,
            optionalInt: nil
        )

        let data = try encodeMessage(original)
        let (_, payload) = try decodeEnvelope(data)
        let decoded = try JSONDecoder().decode(OptionalFieldsMessage.self, from: payload)

        XCTAssertEqual(decoded.required, original.required)
        XCTAssertNil(decoded.optional)
        XCTAssertNil(decoded.optionalInt)
    }

    func testOptionalFieldsWithValues() throws {
        // Message with optional fields populated
        let original = OptionalFieldsMessage(
            required: "required",
            optional: "optional value",
            optionalInt: 123
        )

        let data = try encodeMessage(original)
        let (_, payload) = try decodeEnvelope(data)
        let decoded = try JSONDecoder().decode(OptionalFieldsMessage.self, from: payload)

        XCTAssertEqual(decoded.required, original.required)
        XCTAssertEqual(decoded.optional, "optional value")
        XCTAssertEqual(decoded.optionalInt, 123)
    }

    func testLargePayload() throws {
        // Message with large data
        let longString = String(repeating: "A", count: 10000)
        let manyTags = (0..<100).map { "tag\($0)" }
        var largeMetadata: [String: String] = [:]
        for i in 0..<50 {
            largeMetadata["key\(i)"] = "value\(i)"
        }

        let original = ComplexMessage(
            id: UUID(),
            timestamp: Date(),
            count: Int.max,
            isActive: true,
            tags: manyTags,
            metadata: largeMetadata
        )

        let data = try encodeMessage(original)
        let (messageType, payload) = try decodeEnvelope(data)
        let decoded = try JSONDecoder().decode(ComplexMessage.self, from: payload)

        XCTAssertEqual(messageType, "ComplexMessage")
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.tags.count, 100)
        XCTAssertEqual(decoded.metadata?.count, 50)
    }

    func testSpecialCharactersInStrings() throws {
        // Message with special characters, unicode, emoji
        let original = SimpleMessage(text: "Hello 👋 World! \n\t Special: \"quotes\" & <tags> 日本語")
        let data = try encodeMessage(original)
        let (_, payload) = try decodeEnvelope(data)
        let decoded = try JSONDecoder().decode(SimpleMessage.self, from: payload)

        XCTAssertEqual(decoded.text, original.text)
    }

    func testEmptyArraysAndDictionaries() throws {
        // Message with empty collections
        let original = ComplexMessage(
            id: UUID(),
            timestamp: Date(),
            count: 0,
            isActive: false,
            tags: [],
            metadata: [:]
        )

        let data = try encodeMessage(original)
        let (_, payload) = try decodeEnvelope(data)
        let decoded = try JSONDecoder().decode(ComplexMessage.self, from: payload)

        XCTAssertTrue(decoded.tags.isEmpty)
        XCTAssertEqual(decoded.metadata?.count, 0)
    }

    // MARK: - Message Type Routing Simulation

    func testMessageTypeRouting() throws {
        // Simulate how the receiver would route messages based on type
        let simpleMessage = SimpleMessage(text: "Route me!")
        let customMessage = CustomTypeMessage(value: 42)

        let simpleData = try encodeMessage(simpleMessage)
        let customData = try encodeMessage(customMessage)

        // Simulate receiver checking message type
        let (simpleType, simplePayload) = try decodeEnvelope(simpleData)
        let (customType, customPayload) = try decodeEnvelope(customData)

        // Route based on type
        var routedSimple: SimpleMessage?
        var routedCustom: CustomTypeMessage?

        if simpleType == SimpleMessage.messageType {
            routedSimple = try JSONDecoder().decode(SimpleMessage.self, from: simplePayload)
        }

        if customType == CustomTypeMessage.messageType {
            routedCustom = try JSONDecoder().decode(CustomTypeMessage.self, from: customPayload)
        }

        XCTAssertNotNil(routedSimple)
        XCTAssertNotNil(routedCustom)
        XCTAssertEqual(routedSimple?.text, "Route me!")
        XCTAssertEqual(routedCustom?.value, 42)
    }

    func testMismatchedTypeDoesNotDecode() throws {
        // Attempting to decode wrong type should fail
        let simpleMessage = SimpleMessage(text: "I am simple")
        let data = try encodeMessage(simpleMessage)
        let (messageType, payload) = try decodeEnvelope(data)

        // Type check should prevent wrong decoding
        XCTAssertNotEqual(messageType, CustomTypeMessage.messageType)

        // Even if we tried to decode as wrong type, the receiver should filter by messageType first
        // This simulates proper routing behavior
        if messageType == CustomTypeMessage.messageType {
            XCTFail("Should not attempt to decode as CustomTypeMessage")
        }
    }
}
