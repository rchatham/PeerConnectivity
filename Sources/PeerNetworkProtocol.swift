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

internal struct PeerNetworkFrame : Equatable {

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
        guard data.count >= 5 else { return nil }
        guard let kind = PeerNetworkFrameKind(rawValue: data[data.startIndex]) else { return nil }

        let lengthStart = data.index(after: data.startIndex)
        let lengthEnd = data.index(lengthStart, offsetBy: 4)
        let payloadLength = data[lengthStart..<lengthEnd].reduce(UInt32(0)) { value, byte in
            return (value << 8) | UInt32(byte)
        }

        guard UInt64(payloadLength) <= UInt64(Int.max) else { return nil }
        let expectedCount = 5 + Int(payloadLength)
        guard data.count == expectedCount else { return nil }

        let payloadStart = lengthEnd
        let payload = data[payloadStart..<data.endIndex]
        return PeerNetworkFrame(kind: kind, payload: Data(payload))
    }
}
