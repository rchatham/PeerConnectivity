//
//  PeerConnectionManager+UI.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 6/3/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import PeerConnectivity
#if canImport(UIKit)
import UIKit

extension PeerConnectionManager {

    /**
     Initializer for a connection manager using the current iOS device name as the display name.

     - parameter serviceType: The requested service type describing the channel on which peers are able to connect.
     - parameter connectionType: Takes a PeerConnectionType case determining the default behavior of the framework.

     - Returns: A fully initialized `PeerConnectionManager`.
     */
    public convenience init(serviceType: ServiceType,
                            connectionType: PeerConnectionType = .automatic) {
        self.init(serviceType: serviceType, connectionType: connectionType, displayName: UIDevice.current.name)
    }

    /**
     Returns a browser view controller if the connectionType was set to `.InviteOnly` or returns `nil` if not.

     - parameter callback: Events sent back with cases `.DidFinish` and `.DidCancel`.
     - parameter peerFilter: Optional synchronous filter used before nearby peers are presented.

     - Returns: A browser view controller for inviting available peers nearby if connection type is `.InviteOnly` or `nil` otherwise.
     */
    public func browserViewController(_ callback: @escaping (PeerBrowserViewControllerEvent)->Void,
                                      peerFilter: PeerBrowserViewControllerPeerFilter? = nil) -> UIViewController? {
        switch connectionType {
        case .inviteOnly:
            let browserAssisstant = PeerBrowserAssisstant(session: multipeerSession, serviceType: peerServiceType)
            return browserAssisstant.peerBrowserViewController(callback, peerFilter: peerFilter)
        default: return nil
        }
    }
}
#endif
