//
//  PeerBrowserViewControllerEventProducer.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

/** 
 Event callbacks associated with user interaction with the browser view controller.
 
 - None: No event was passed.
 - DidFinish: The user did finish picking peers in the browser view controller.
 - WasCancelled: The user did cancel their interaction with the browser view controller.
 */
public enum PeerBrowserViewControllerEvent {
    /// No event was passed.
    case None
    /// The user did finish picking peers in the browser view controller.
    case DidFinish
    /// The user did cancel their interaction with the browser view controller.
    case WasCancelled
    
//    case ShouldPresentNearbyPeer
}

internal class PeerBrowserViewControllerEventProducer: NSObject {
    
    private let observer: Observable<PeerBrowserViewControllerEvent>

    internal init(observer: Observable<PeerBrowserViewControllerEvent>) {
        self.observer = observer
    }
}

extension PeerBrowserViewControllerEventProducer: MCBrowserViewControllerDelegate {

//    func browserViewController(browserViewController: MCBrowserViewController, shouldPresentNearbyPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) -> Bool {
//        return true
//    }
    
    internal func browserViewControllerDidFinish(browserViewController: MCBrowserViewController) {
        
        let event : PeerBrowserViewControllerEvent = .DidFinish
        self.observer.value = event
        
        browserViewController.dismissViewControllerAnimated(true, completion: nil)
    }
    
    internal func browserViewControllerWasCancelled(browserViewController: MCBrowserViewController) {
        
        let event : PeerBrowserViewControllerEvent = .WasCancelled
        self.observer.value = event
        
        browserViewController.dismissViewControllerAnimated(true, completion: nil)
    }
}
