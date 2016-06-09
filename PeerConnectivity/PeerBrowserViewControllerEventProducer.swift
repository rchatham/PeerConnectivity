//
//  PeerBrowserViewControllerEventProducer.swift
//  GameController
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal enum PeerBrowserViewControllerEvent {
    //    case ShouldPresentNearbyPeer
    case None
    case DidFinish
    case WasCancelled
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
