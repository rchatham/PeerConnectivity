//
//  BluetoothPeerRadio.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import CoreBluetooth
import CryptoKit
import PeerConnectivity

/**
 Why the Bluetooth backend could not browse or advertise. Delivered as the underlying error of
 `PeerConnectionError.browsingFailed(underlying:)` or `.advertisingFailed(underlying:)`.
 */
public enum PeerBluetoothError : Error, Equatable {
    /** Bluetooth is turned off. Discovery resumes when it is turned back on. */
    case poweredOff
    /** The user denied Bluetooth access, or the app's Info.plist lacks `NSBluetoothAlwaysUsageDescription`. */
    case unauthorized
    /** This device does not support Bluetooth LE peripheral and central roles. */
    case unsupported

    internal init?(state: CBManagerState) {
        switch state {
        case .poweredOff: self = .poweredOff
        case .unauthorized: self = .unauthorized
        case .unsupported: self = .unsupported
        default: return nil
        }
    }
}

/// The GATT layout both roles agree on.
@available(iOS 13.0, macOS 10.15, *)
internal enum BluetoothPeerService {

    /// The largest value an ATT attribute can hold.
    internal static let maxIdentityPayloadLength = 512

    /// Holds the peer's identity and app discovery info, encoded as `identityPayload(for:)` does.
    internal static let identityCharacteristicUUID = CBUUID(string: "3A5E8C10-6F2B-4C1D-9B7E-50C0A1D2E3F4")
    /// Holds the L2CAP PSM, little-endian, under the UUID Apple reserves for it.
    internal static let psmCharacteristicUUID = CBUUID(string: CBUUIDL2CAPPSMCharacteristicString)

    /// A per-service-type UUID, so apps (and service types within an app) never see each other,
    /// as Bonjour service types keep them apart on the Network backend.
    internal static func serviceUUID(for serviceType: ServiceType) -> CBUUID {
        var bytes = Array(SHA256.hash(data: Data("PeerConnectivity.Bluetooth.service.\(serviceType)".utf8)).prefix(16))
        // Mark it as a name-based (version 5 layout) UUID so it reads as a well-formed UUID.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return CBUUID(data: Data(bytes))
    }

    /// The same keys the Network backend puts in its Bonjour TXT record, as sorted JSON.
    /// Nil when the result would not fit in one attribute.
    internal static func identityPayload(for info: PeerNetworkDiscoveryInfo) -> Data? {
        guard let payload = try? JSONSerialization.data(withJSONObject: info.txtRecordDictionary, options: [.sortedKeys]),
            payload.count <= maxIdentityPayloadLength else {
            return nil
        }
        return payload
    }

    /// Remote payloads are untrusted: anything malformed or reserved is rejected or dropped.
    internal static func discoveryInfo(fromIdentityPayload payload: Data) -> PeerNetworkDiscoveryInfo? {
        guard payload.count <= maxIdentityPayloadLength,
            let dictionary = (try? JSONSerialization.jsonObject(with: payload)) as? [String:String] else {
            return nil
        }
        return PeerNetworkDiscoveryInfo(txtRecordDictionary: dictionary)
    }
}

/// An open L2CAP channel's streams, with the object that must stay alive for them to stay open.
internal struct BluetoothChannelStreams {
    internal let inputStream : InputStream
    internal let outputStream : OutputStream
    internal let owner : AnyObject?
}

/// The peripheral role: publishes the service and accepts channels, advertising only when asked,
/// so a peer can stay reachable to connected peers without being discoverable.
internal protocol BluetoothPeerAdvertising : AnyObject {
    func start()
    func cancel()
    func setAdvertising(_ isAdvertising: Bool)
}

internal struct BluetoothPeerAdvertisingHandlers {
    internal let channelOpened : (BluetoothChannelStreams) -> Void
    internal let failed : (PeerConnectionError) -> Void
}

/// The central role: reports every sighting of a peer, and opens channels on request.
internal protocol BluetoothPeerScanning : AnyObject {
    func start()
    func cancel()
    func openChannel(to peripheral: UUID)
}

internal struct BluetoothPeerScanningHandlers {
    /// Called for each advertisement from a peer whose identity has been read.
    internal let sighted : (UUID, PeerNetworkDiscoveryInfo) -> Void
    internal let channelOpened : (UUID, BluetoothChannelStreams) -> Void
    internal let channelFailed : (UUID, Error?) -> Void
    internal let failed : (PeerConnectionError) -> Void
}

/// Builds both roles. Core Bluetooth in apps; a simulated radio in tests.
internal struct BluetoothPeerRadio {
    internal let makeAdvertising : (ServiceType, Data, BluetoothPeerAdvertisingHandlers) -> BluetoothPeerAdvertising
    internal let makeScanning : (ServiceType, BluetoothPeerScanningHandlers) -> BluetoothPeerScanning

    @available(iOS 13.0, macOS 10.15, *)
    internal static let coreBluetooth = BluetoothPeerRadio(
        makeAdvertising: { serviceType, identityPayload, handlers in
            return CoreBluetoothPeerPeripheral(serviceUUID: BluetoothPeerService.serviceUUID(for: serviceType),
                identityPayload: identityPayload,
                handlers: handlers)
        },
        makeScanning: { serviceType, handlers in
            return CoreBluetoothPeerCentral(serviceUUID: BluetoothPeerService.serviceUUID(for: serviceType),
                handlers: handlers)
        })
}

/// Stands in for the peripheral role when it could not be configured, reporting why on start.
internal final class FailedBluetoothPeerAdvertising : BluetoothPeerAdvertising {

    fileprivate let error : PeerConnectionError?
    fileprivate let failed : ((PeerConnectionError) -> Void)?

    internal init(error: PeerConnectionError? = nil, failed: ((PeerConnectionError) -> Void)? = nil) {
        self.error = error
        self.failed = failed
    }

    internal func start() {
        guard let error = error else { return }
        failed?(error)
    }

    internal func cancel() {}

    internal func setAdvertising(_ isAdvertising: Bool) {}
}
