//
//  PeerBrowserViewControllerEventProducer.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import PeerConnectivity
#if canImport(UIKit)
import UIKit

/**
 Event callbacks associated with user interaction with the browser view controller.

 - none: No event was passed.
 - didFinish: The user did finish picking peers in the browser view controller.
 - wasCancelled: The user did cancel their interaction with the browser view controller.
 */
public enum PeerBrowserViewControllerEvent {
    /// No event was passed.
    case none
    /// The user did finish picking peers in the browser view controller.
    case didFinish
    /// The user did cancel their interaction with the browser view controller.
    case wasCancelled
}

/**
 Synchronous filter used by `MCBrowserViewController` before presenting a nearby peer.

 Discovery info is advertised before a session is established and should be treated as
 public, unauthenticated metadata. Use this only for non-secret filtering, such as protocol
 versions, public capability flags, or non-secret room labels.
 */
public typealias PeerBrowserViewControllerPeerFilter = (Peer, PeerDiscoveryInfo?) -> Bool

internal final class PeerBrowserViewControllerEventProducer: NSObject, MCBrowserViewControllerDelegate {

    fileprivate let callback: (PeerBrowserViewControllerEvent) -> Void
    fileprivate let peerFilter: PeerBrowserViewControllerPeerFilter?

    internal init(callback: @escaping (PeerBrowserViewControllerEvent) -> Void,
                  peerFilter: PeerBrowserViewControllerPeerFilter? = nil) {
        self.callback = callback
        self.peerFilter = peerFilter
    }

    internal func browserViewController(_ browserViewController: MCBrowserViewController,
                                        shouldPresentNearbyPeer peerID: MCPeerID,
                                        withDiscoveryInfo info: [String : String]?) -> Bool {
        guard let peerFilter = peerFilter else { return true }
        let peer = Peer(peerID: peerID, status: .notConnected)
        return peerFilter(peer, info)
    }

    internal func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {

        let event : PeerBrowserViewControllerEvent = .didFinish
        callback(event)

        browserViewController.dismiss(animated: true, completion: nil)
    }

    internal func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {

        let event : PeerBrowserViewControllerEvent = .wasCancelled
        callback(event)

        browserViewController.dismiss(animated: true, completion: nil)
    }
}
#endif
