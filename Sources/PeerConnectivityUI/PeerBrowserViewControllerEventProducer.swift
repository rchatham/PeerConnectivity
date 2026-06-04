//
//  PeerBrowserViewControllerEventProducer.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity
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

//    case shouldPresentNearbyPeer
}

internal final class PeerBrowserViewControllerEventProducer: NSObject, MCBrowserViewControllerDelegate {

    fileprivate let callback: (PeerBrowserViewControllerEvent) -> Void

    internal init(callback: @escaping (PeerBrowserViewControllerEvent) -> Void) {
        self.callback = callback
    }

//    func browserViewController(browserViewController: MCBrowserViewController, shouldPresentNearbyPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) -> Bool {
//        return true
//    }

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
