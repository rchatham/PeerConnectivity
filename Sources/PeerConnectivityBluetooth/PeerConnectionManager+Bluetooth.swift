//
//  PeerConnectionManager+Bluetooth.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import PeerConnectivity

/**
 The radios a `PeerConnectionManager` from `PeerConnectivityBluetooth` uses.
 */
public struct PeerConnectionLinks : OptionSet, Hashable {
    public let rawValue : Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /** Network framework: infrastructure Wi-Fi, Ethernet and peer-to-peer Wi-Fi. Fastest. */
    public static let networkFramework = PeerConnectionLinks(rawValue: 1 << 0)
    /** Bluetooth LE, which keeps working with Wi-Fi turned off. */
    public static let bluetooth = PeerConnectionLinks(rawValue: 1 << 1)
    /** Every radio at once: peers connect over whichever reach them and stay connected while any does. */
    public static let all : PeerConnectionLinks = [.networkFramework, .bluetooth]
}

@available(iOS 13.0, macOS 10.15, *)
extension PeerConnectionManager {

    /**
     Initializes a connection manager that connects nearby peers over the given radios.

     With `.all`, Wi-Fi and Bluetooth run at the same time. A peer reachable over both is
     connected over both and reported once; it stays connected while either link is up, so
     turning Wi-Fi off mid-session is invisible to the app. Data goes over Wi-Fi when it is
     connected and falls back to Bluetooth, retrying a failed send on the other link. Messages
     that switch links can arrive out of order relative to each other.

     The app answers one invitation and one certificate decision per peer, however many links
     carry it. A second link is admitted without asking only while the peer is connected, and
     with certificates only if it presents the certificate the app already accepted.

     Security is the same setting the `.networkFramework` backend takes, applied to every link:
     `.unauthenticated` sends plaintext, `.preSharedKey(_:)` requires the same key on both peers,
     and `.certificate(identity:)` proves each peer holds its certificate's key and leaves trust
     to `certificatePolicy`. Peers interoperate with managers that use only one of the links.

     Bluetooth carries tens of kilobytes per second at room range. Data streams and resource
     transfer are not supported.

     - Important: With `.bluetooth`, the app's Info.plist must contain
       `NSBluetoothAlwaysUsageDescription`. With `.networkFramework`, it needs
       `NSLocalNetworkUsageDescription` and its Bonjour service in `NSBonjourServices`. A radio
       that is off or unauthorized is reported through `.error` while the others keep working;
       Bluetooth reports `PeerBluetoothError` inside `.browsingFailed` or `.advertisingFailed`.

     - parameter serviceType: The channel on which peers connect.
     - parameter links: The radios to use; `.all` for Wi-Fi and Bluetooth together.
     - parameter connectionType: The default connection behavior.
     - parameter displayName: The local user's display name to other peers.
     - parameter securityConfiguration: Certificate and encryption policy.
     - parameter discoveryInfo: Public, unauthenticated metadata for nearby browsers. Network
       framework rules apply, and over Bluetooth the encoded identity must fit in 512 bytes.
     - parameter invitationPolicy: Decides incoming invitations in `.automatic` mode.
     - parameter networkSecurity: The same security setting the `.networkFramework` backend takes.
     - parameter lostPeerTimeout: Seconds without a Bluetooth advertisement before the peer is
       lost on that link. Defaults to 5.
     */
    public convenience init(serviceType: ServiceType,
        links: PeerConnectionLinks,
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
            transportFactory: .links(links, security: networkSecurity, lostPeerTimeout: lostPeerTimeout),
            registersSharedManager: true)
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension PeerConnectionTransportFactory {

    internal static func links(_ links: PeerConnectionLinks,
        security: PeerConnectionNetworkSecurity,
        lostPeerTimeout: TimeInterval) -> PeerConnectionTransportFactory {
        precondition(!links.isEmpty, "PeerConnectivity: choose at least one link")
        var factories : [PeerConnectionTransportFactory] = []
        if links.contains(.networkFramework) {
            factories.append(.networkFramework(security: security))
        }
        if links.contains(.bluetooth) {
            factories.append(.bluetooth(security: security, lostPeerTimeout: lostPeerTimeout))
        }
        return factories.count == 1 ? factories[0] : .combined(factories, backend: .networkFrameworkAndBluetooth)
    }
}
