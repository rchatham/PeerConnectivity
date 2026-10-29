//
//  PeerNetworkProtocol.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

internal struct PeerNetworkBonjourService : Equatable {

    internal let serviceType : String
    internal let bonjourType : String

    internal init(serviceType: ServiceType) {
        self.serviceType = serviceType
        if serviceType.hasPrefix("_") && serviceType.hasSuffix("._tcp") {
            bonjourType = serviceType
        } else {
            bonjourType = "_\(serviceType)._tcp"
        }
    }
}

internal struct PeerNetworkDiscoveryInfo : Equatable {

    fileprivate static let identifierKey = "pc-id"
    fileprivate static let displayNameKey = "pc-name"
    fileprivate static let protocolVersionKey = "pc-v"
    fileprivate static let maxTXTEntryByteLength = 255
    fileprivate static let maxDisplayNameByteLength = 247

    internal let identity : PeerIdentity
    internal let protocolVersion : Int

    internal init(identity: PeerIdentity, protocolVersion: Int = PeerNetworkHandshake.currentProtocolVersion) {
        let identifier = PeerNetworkDiscoveryInfo.truncate(identity.identifier,
            toUTF8ByteCount: PeerIdentity.maxIdentifierByteLength)
        let displayName = PeerNetworkDiscoveryInfo.truncate(identity.displayName,
            toUTF8ByteCount: PeerNetworkDiscoveryInfo.maxDisplayNameByteLength)
        self.identity = PeerIdentity(identifier: identifier, displayName: displayName)
        self.protocolVersion = protocolVersion
    }

    internal var txtRecordDictionary : [String:String] {
        return [
            PeerNetworkDiscoveryInfo.identifierKey: identity.identifier,
            PeerNetworkDiscoveryInfo.displayNameKey: identity.displayName,
            PeerNetworkDiscoveryInfo.protocolVersionKey: String(protocolVersion),
        ]
    }

    internal init?(txtRecordDictionary: [String:String]) {
        guard let identifier = txtRecordDictionary[PeerNetworkDiscoveryInfo.identifierKey],
            let displayName = txtRecordDictionary[PeerNetworkDiscoveryInfo.displayNameKey],
            let protocolVersionText = txtRecordDictionary[PeerNetworkDiscoveryInfo.protocolVersionKey],
            let protocolVersion = Int(protocolVersionText),
            protocolVersion == PeerNetworkHandshake.currentProtocolVersion,
            PeerIdentity.isValidIdentifier(identifier),
            !displayName.isEmpty,
            displayName.utf8.count <= PeerNetworkDiscoveryInfo.maxDisplayNameByteLength,
            PeerNetworkDiscoveryInfo.isTXTEntryByteSafe(key: PeerNetworkDiscoveryInfo.identifierKey,
                value: identifier),
            PeerNetworkDiscoveryInfo.isTXTEntryByteSafe(key: PeerNetworkDiscoveryInfo.displayNameKey,
                value: displayName),
            PeerNetworkDiscoveryInfo.isTXTEntryByteSafe(key: PeerNetworkDiscoveryInfo.protocolVersionKey,
                value: protocolVersionText) else { return nil }

        self.identity = PeerIdentity(identifier: identifier, displayName: displayName)
        self.protocolVersion = protocolVersion
    }

    fileprivate static func isTXTEntryByteSafe(key: String, value: String) -> Bool {
        return key.utf8.count + 1 + value.utf8.count <= maxTXTEntryByteLength
    }

    fileprivate static func truncate(_ value: String, toUTF8ByteCount maxByteCount: Int) -> String {
        guard value.utf8.count > maxByteCount else { return value }

        let utf8 = value.utf8
        var endIndex = utf8.index(utf8.startIndex, offsetBy: maxByteCount)
        while endIndex > utf8.startIndex && utf8[endIndex] & 0xC0 == 0x80 {
            endIndex = utf8.index(before: endIndex)
        }
        return String(decoding: utf8[..<endIndex], as: UTF8.self)
    }
}

internal struct PeerNetworkHandshake : Codable, Equatable {

    internal static let currentProtocolVersion = 1

    internal let protocolVersion : Int
    internal let identity : PeerIdentity

    internal init(identity: PeerIdentity, protocolVersion: Int = PeerNetworkHandshake.currentProtocolVersion) {
        self.identity = identity
        self.protocolVersion = protocolVersion
    }
}

internal enum PeerNetworkFrameKind : UInt8 {
    case data = 1
    case handshake = 2
}

internal enum PeerNetworkFrameDecodeResult {
    case frame(PeerNetworkFrame, consumedBytes: Int)
    case incomplete
    case invalid
}

internal enum PeerNetworkFrameDecoderError : Error, Equatable {
    case invalidFrame
}

internal struct PeerNetworkFrame : Equatable {

    fileprivate static let headerLength = 5
    internal static let maxPayloadLength = 1024 * 1024

    internal let kind : PeerNetworkFrameKind
    internal let payload : Data

    internal init(kind: PeerNetworkFrameKind, payload: Data) {
        self.kind = kind
        self.payload = payload
    }

    internal func encoded() -> Data {
        var data = Data()
        data.append(kind.rawValue)

        var payloadLength = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &payloadLength) { bytes in
            data.append(contentsOf: bytes)
        }

        data.append(payload)
        return data
    }

    internal static func decode(_ data: Data) -> PeerNetworkFrame? {
        switch decodeNext(in: data) {
        case .frame(let frame, consumedBytes: let consumedBytes) where consumedBytes == data.count:
            return frame
        default:
            return nil
        }
    }

    internal static func decodeNext(in data: Data) -> PeerNetworkFrameDecodeResult {
        guard data.count >= headerLength else { return .incomplete }
        guard let kind = PeerNetworkFrameKind(rawValue: data[data.startIndex]) else { return .invalid }

        let lengthStart = data.index(after: data.startIndex)
        let lengthEnd = data.index(lengthStart, offsetBy: 4)
        let payloadLength = data[lengthStart..<lengthEnd].reduce(UInt32(0)) { value, byte in
            return (value << 8) | UInt32(byte)
        }

        guard payloadLength <= UInt32(maxPayloadLength) else { return .invalid }
        let expectedCount = headerLength + Int(payloadLength)
        guard data.count >= expectedCount else { return .incomplete }

        let payloadStart = lengthEnd
        let payloadEnd = data.index(data.startIndex, offsetBy: expectedCount)
        let payload = data[payloadStart..<payloadEnd]
        return .frame(PeerNetworkFrame(kind: kind, payload: Data(payload)), consumedBytes: expectedCount)
    }
}

internal struct PeerNetworkFrameDecoder {

    fileprivate var buffer = Data()
    fileprivate var isTerminal = false

    internal init() {}

    internal mutating func append(_ data: Data) throws -> [PeerNetworkFrame] {
        guard !isTerminal else { throw PeerNetworkFrameDecoderError.invalidFrame }

        buffer.append(data)
        var frames : [PeerNetworkFrame] = []
        var consumedBytes = 0

        while consumedBytes < buffer.count {
            let unreadStart = buffer.index(buffer.startIndex, offsetBy: consumedBytes)
            switch PeerNetworkFrame.decodeNext(in: buffer[unreadStart...]) {
            case .frame(let frame, consumedBytes: let frameLength):
                frames.append(frame)
                consumedBytes += frameLength
            case .incomplete:
                if consumedBytes > 0 {
                    buffer.removeFirst(consumedBytes)
                }
                return frames
            case .invalid:
                buffer.removeAll(keepingCapacity: true)
                isTerminal = true
                throw PeerNetworkFrameDecoderError.invalidFrame
            }
        }

        buffer.removeAll(keepingCapacity: true)
        return frames
    }
}
