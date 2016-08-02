//
//  PeerAdvertiser.swift
//  GameController
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal enum PeerAdvertiserEvent {
    case None
    case DidNotStartAdvertisingPeer
    case DidReceiveInvitationFromPeer(peer: Peer, withContext: NSData?, invitationHandler: (Bool, PeerSession) -> Void)
}

internal class PeerAdvertiserEventProducer: NSObject {
    
    private let observer : Observable<PeerAdvertiserEvent>
    
    internal init(observer: Observable<PeerAdvertiserEvent>) {
        self.observer = observer
    }
}

extension PeerAdvertiserEventProducer: MCNearbyServiceAdvertiserDelegate {

    internal func advertiser(advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: NSError) {
        NSLog("%@", "didNotStartAdvertisingPeer: \(error)")
        
        let event: PeerAdvertiserEvent = .DidNotStartAdvertisingPeer
        self.observer.value = event
    }
    
    internal func advertiser(advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: NSData?, invitationHandler: (Bool, MCSession) -> Void) {
        NSLog("%@", "didReceiveInvitationFromPeer \(peerID)")
        
        let handler : ((Bool, PeerSession) -> Void) = { (accept, session) in
            invitationHandler(accept, session.session)
        }
        
        let peer = Peer(peerID: peerID, status: .NotConnected)
        let event: PeerAdvertiserEvent = .DidReceiveInvitationFromPeer(peer: peer, withContext: context, invitationHandler: handler)
        self.observer.value = event
    }
}
