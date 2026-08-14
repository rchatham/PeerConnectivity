//
//  NetworkPeerStateMapping.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import Network

@available(iOS 13.0, macOS 10.15, *)
internal enum NetworkPeerStateMapping {

    internal static func status(for state: NWConnection.State) -> Peer.Status? {
        switch state {
        case .setup:
            return .notConnected
        case .waiting, .preparing:
            return .connecting
        case .ready:
            return .connected
        case .failed, .cancelled:
            return .notConnected
        @unknown default:
            return nil
        }
    }

    internal static func shouldEmitDevicesChanged(for state: NWConnection.State) -> Bool {
        return status(for: state) != nil
    }

    internal static func shouldAttemptReconnect(for state: NWConnection.State) -> Bool {
        switch state {
        case .waiting, .failed:
            return true
        default:
            return false
        }
    }
}
