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

    /**
     Maps a Network browser state to the error reported through `PeerConnectionEvent.error`.

     - Returns: The error to report, or `nil` when the state should not be surfaced.
     */
    internal static func error(for state: NWBrowser.State) -> PeerConnectionError? {
        switch state {
        case .failed(let error):
            return isLocalNetworkDenial(error) ? .localNetworkAccessDenied(underlying: error) : .browsingFailed(underlying: error)
        case .waiting(let error):
            // Other waiting states recover on their own; only the permission denial needs the app.
            return isLocalNetworkDenial(error) ? .localNetworkAccessDenied(underlying: error) : nil
        default:
            return nil
        }
    }

    /**
     Maps a Network listener state to the error reported through `PeerConnectionEvent.error`.

     - Returns: The error to report, or `nil` when the state should not be surfaced.
     */
    internal static func error(for state: NWListener.State) -> PeerConnectionError? {
        switch state {
        case .failed(let error):
            return isLocalNetworkDenial(error) ? .localNetworkAccessDenied(underlying: error) : .advertisingFailed(underlying: error)
        case .waiting(let error):
            return isLocalNetworkDenial(error) ? .localNetworkAccessDenied(underlying: error) : nil
        default:
            return nil
        }
    }

    /// Local Network denial surfaces as a DNS policy error rather than a `.failed` state.
    internal static func isLocalNetworkDenial(_ error: NWError) -> Bool {
        guard case .dns(let code) = error else { return false }
        return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
    }
}
