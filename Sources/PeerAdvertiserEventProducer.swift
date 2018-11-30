//
//  PeerAdvertiser.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal enum PeerAdvertiserEvent {
    case none
    case didNotStartAdvertisingPeer(Error)
    case didReceiveInvitationFromPeer(peer: Peer, withContext: Data?, invitationHandler: (Bool, PeerSession) -> Void)
}

internal class PeerAdvertiserEventProducer: NSObject {
    
    fileprivate let observer: Observable<PeerAdvertiserEvent>
    
    internal init(observer: Observable<PeerAdvertiserEvent>) {
        self.observer = observer
    }
}

extension PeerAdvertiserEventProducer: MCNearbyServiceAdvertiserDelegate {

    internal func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        NSLog("%@", "didNotStartAdvertisingPeer: \(error)")
        
        let event: PeerAdvertiserEvent = .didNotStartAdvertisingPeer(error)
        self.observer.value = event
    }
    
    internal func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                             withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        NSLog("%@", "didReceiveInvitationFromPeer \(peerID)")
        
        let handler: ((Bool, PeerSession) -> Void) = { (accept, session) in
            NSLog("%@", "invitationHandler \(peerID), accept \(accept), session \(session)")
            invitationHandler(accept, session.session)
        }
        
        let peer = Peer(peerID: peerID, status: .notConnected)
        let event: PeerAdvertiserEvent = .didReceiveInvitationFromPeer(peer: peer, withContext: context, invitationHandler: handler)
        self.observer.value = event
    }
}
