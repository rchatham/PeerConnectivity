//
//  PeerBrowser.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

public typealias DiscoveryInfo = [String: String]

internal enum PeerBrowserEvent: CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case didNotStartBrowsingForPeers(Error)
    case foundPeer(Peer, DiscoveryInfo?)
    case lostPeer(Peer)

    // MARK: - CustomStringConvertible, CustomDebugStringConvertible

    var description: String {
        switch self {
        case .none: return "none"
        case .didNotStartBrowsingForPeers(let error):
            return "didNotStartBrowsingForPeers(error: \(error))"

        case .foundPeer(let peer, let info):
            return "foundPeer(peer: \(peer.peerID))\n\tdiscovery: \(info ?? [:])"
        case .lostPeer(let peer):
            return "lostPeer(peer: \(peer.peerID))"

        default: return Mirror(reflecting: self).children.first?.label ?? ""
        }
    }

    var debugDescription: String {
        return description
    }

}

internal class PeerBrowserEventProducer: NSObject {
    
    fileprivate let observer: Observable<PeerBrowserEvent>
    
    internal init(observer: Observable<PeerBrowserEvent>) {
        self.observer = observer
    }
}

extension PeerBrowserEventProducer: MCNearbyServiceBrowserDelegate {

    internal func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        let event: PeerBrowserEvent = .didNotStartBrowsingForPeers(error)
        logger.error("PeerBrowserEventProducer - \(event)")

        self.observer.value = event
    }
    
    internal func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                          withDiscoveryInfo info: [String: String]?) {
        let peer = Peer(peerID: peerID, status: .available, info: info)
        let event: PeerBrowserEvent = .foundPeer(peer, info)

        logger.info("PeerBrowserEventProducer - \(event)")
        self.observer.value = event
    }
    
    internal func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peer = Peer(peerID: peerID, status: .unavailable)
        let event: PeerBrowserEvent = .lostPeer(peer)

        logger.info("PeerBrowserEventProducer - \(event)")
        self.observer.value = event
    }

}
