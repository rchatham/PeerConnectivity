//
//  PeerBrowser.swift
//  GameController
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal enum PeerBrowserEvent {
    case None
    case DidNotStartBrowsingForPeers
    case FoundPeer(Peer)
    case LostPeer(Peer)
}

internal class PeerBrowserEventProducer: NSObject {
    
    private let observer : Observable<PeerBrowserEvent>
    
    internal init(observer: Observable<PeerBrowserEvent>) {
        self.observer = observer
    }
}

extension PeerBrowserEventProducer: MCNearbyServiceBrowserDelegate {

    internal func browser(browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: NSError) {
        NSLog("%@", "didNotStartBrowsingForPeers: \(error)")
        
        let event : PeerBrowserEvent = .DidNotStartBrowsingForPeers
        self.observer.value = event
    }
    
    internal func browser(browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        NSLog("%@", "foundPeer: \(peerID)")
        
        let peer = Peer.NotConnected(peerID)
        let event : PeerBrowserEvent = .FoundPeer(peer)
        self.observer.value = event
    }
    
    internal func browser(browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        NSLog("%@", "lostPeer: \(peerID)")
        
        let peer = Peer.NotConnected(peerID)
        let event : PeerBrowserEvent = .LostPeer(peer)
        self.observer.value = event
    }

}
