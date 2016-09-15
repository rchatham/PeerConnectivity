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
    case none
    /// The user did finish picking peers in the browser view controller.
    case didFinish
    /// The user did cancel their interaction with the browser view controller.
    case wasCancelled
    
//    case ShouldPresentNearbyPeer
}

internal class PeerBrowserViewControllerEventProducer: NSObject {
    
    fileprivate let observer: Observable<PeerBrowserViewControllerEvent>

    internal init(observer: Observable<PeerBrowserViewControllerEvent>) {
        self.observer = observer
    }
}

extension PeerBrowserViewControllerEventProducer: MCBrowserViewControllerDelegate {

//    func browserViewController(browserViewController: MCBrowserViewController, shouldPresentNearbyPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) -> Bool {
//        return true
//    }
    
    internal func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        
        let event : PeerBrowserViewControllerEvent = .didFinish
        self.observer.value = event
        
        browserViewController.dismiss(animated: true, completion: nil)
    }
    
    internal func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        
        let event : PeerBrowserViewControllerEvent = .wasCancelled
        self.observer.value = event
        
        browserViewController.dismiss(animated: true, completion: nil)
    }
}
