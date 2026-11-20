//
//  PeerConnectionManager+Bluetooth.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import PeerConnectivity

@available(iOS 13.0, macOS 10.15, *)
extension PeerConnectionManager {

    /**
     Initializes a connection manager that finds and connects nearby peers over Bluetooth LE,
     so peers can reach each other with Wi-Fi turned off. Peers only see other managers
     created with this initializer and the same service type.

     Security matches the `.networkFramework` backend, so swapping backends needs no security
     changes: `.unauthenticated` sends plaintext, `.preSharedKey(_:)` requires the same key on
     both peers and encrypts with forward secrecy, and `.certificate(identity:)` proves each
     peer holds its certificate's key and leaves trust to `certificatePolicy`.

     Bluetooth carries tens of kilobytes per second at room range, so keep messages small.
     Data streams and resource transfer are not supported.

     - Important: The app's Info.plist must contain `NSBluetoothAlwaysUsageDescription`.
       Bluetooth being off or unauthorized is reported through `.error` as
       `PeerConnectionError.browsingFailed(underlying:)` or `.advertisingFailed(underlying:)`
       wrapping a `PeerBluetoothError`.

     - parameter serviceType: The channel on which peers connect, as for the other backends.
     - parameter connectionType: The default connection behavior.
     - parameter displayName: The local user's display name to other peers.
     - parameter securityConfiguration: Certificate and encryption policy.
     - parameter discoveryInfo: Public, unauthenticated metadata for nearby browsers. The same
       rules as the Network backend apply, and the encoded identity must fit in 512 bytes.
     - parameter invitationPolicy: Decides incoming invitations in `.automatic` mode.
     - parameter networkSecurity: The same security setting the `.networkFramework` backend takes.
     - parameter lostPeerTimeout: Seconds without seeing a peer's advertisement before
       `.lostPeer` is reported. Defaults to 5.
     */
    public convenience init(bluetoothServiceType serviceType: ServiceType,
        connectionType: PeerConnectionType = .automatic,
        displayName: String = {
            #if os(macOS)
            return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            #else
            return ProcessInfo.processInfo.hostName
            #endif
        }(),
        securityConfiguration: PeerSecurityConfiguration = .default,
        discoveryInfo: PeerDiscoveryInfo? = nil,
        invitationPolicy: PeerInvitationPolicy = .acceptAll,
        networkSecurity: PeerConnectionNetworkSecurity = .unauthenticated,
        lostPeerTimeout: TimeInterval = 5) {
        self.init(serviceType: serviceType,
            connectionType: connectionType,
            displayName: displayName,
            securityConfiguration: securityConfiguration,
            discoveryInfo: discoveryInfo,
            invitationPolicy: invitationPolicy,
            networkSecurity: networkSecurity,
            transportFactory: .bluetooth(security: networkSecurity, lostPeerTimeout: lostPeerTimeout),
            registersSharedManager: true)
    }
}
