//
//  PeerBrowser.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal enum PeerBrowserEvent {
    case none
    case didNotStartBrowsingForPeers
    case foundPeer(Peer)
    case lostPeer(Peer)
}

internal class PeerBrowserEventProducer: NSObject {
    
    fileprivate let observer : Observable<PeerBrowserEvent>
    
    internal init(observer: Observable<PeerBrowserEvent>) {
        self.observer = observer
    }
}

extension PeerBrowserEventProducer: MCNearbyServiceBrowserDelegate {

    internal func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        NSLog("%@", "didNotStartBrowsingForPeers: \(error)")
        
        let event : PeerBrowserEvent = .didNotStartBrowsingForPeers
        self.observer.value = event
    }
    
    internal func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        NSLog("%@", "foundPeer: \(peerID)")
        
        let peer = Peer(peerID: peerID, status: .notConnected)
        let event : PeerBrowserEvent = .foundPeer(peer)
        self.observer.value = event
    }
    
    internal func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        NSLog("%@", "lostPeer: \(peerID)")
        
        let peer = Peer(peerID: peerID, status: .notConnected)
        let event : PeerBrowserEvent = .lostPeer(peer)
        self.observer.value = event
    }

}
