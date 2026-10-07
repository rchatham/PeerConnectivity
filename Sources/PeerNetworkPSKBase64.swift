//
//  PeerNetworkPSKBase64.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 8/10/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import Security

internal enum PeerNetworkPSKBase64Error : Error, Equatable {
    case empty
    case containsWhitespace
    case malformed
    case tooShort(actualByteCount: Int, minimumByteCount: Int)
}

internal enum PeerNetworkPSKBase64 {
    internal static let minimumByteCount = 32

    /// Strictly validates and decodes demo TLS-PSK input without accepting whitespace.
    internal static func decode(_ value: String) -> Result<Data, PeerNetworkPSKBase64Error> {
        guard !value.isEmpty else { return .failure(.empty) }
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return .failure(.containsWhitespace)
        }
        guard let data = Data(base64Encoded: value), !data.isEmpty else { return .failure(.malformed) }
        guard data.count >= minimumByteCount else {
            return .failure(.tooShort(actualByteCount: data.count, minimumByteCount: minimumByteCount))
        }
        return .success(data)
    }
}

internal struct PeerNetworkTestKeyGenerationError : Error, Equatable {
    internal let status : Int32
}

internal enum PeerNetworkTestKeyGenerator {
    internal typealias FillRandomBytes = (UnsafeMutableRawBufferPointer) -> Int32

    /// Generates at least 32 bytes of in-memory Base64 test key material. The caller controls its lifetime.
    internal static func generateBase64(
        byteCount: Int = PeerNetworkPSKBase64.minimumByteCount,
        fillRandomBytes: FillRandomBytes = { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }) -> Result<String, PeerNetworkTestKeyGenerationError> {
        guard byteCount >= PeerNetworkPSKBase64.minimumByteCount else {
            return .failure(PeerNetworkTestKeyGenerationError(status: errSecParam))
        }
        var data = Data(count: byteCount)
        let status = data.withUnsafeMutableBytes(fillRandomBytes)
        guard status == errSecSuccess else {
            return .failure(PeerNetworkTestKeyGenerationError(status: status))
        }
        return .success(data.base64EncodedString())
    }
}
