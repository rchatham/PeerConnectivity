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
