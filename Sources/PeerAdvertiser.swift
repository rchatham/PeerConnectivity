//
//  PeerAdvertiser.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal struct PeerAdvertiser : PeerAdvertiserTransport {
    
    fileprivate let session : PeerSessionTransport
    fileprivate let advertiser : MCNearbyServiceAdvertiser
    fileprivate let eventProducer : PeerAdvertiserEventProducer
    
    internal init(session: PeerSessionTransport, serviceType: ServiceType, eventProducer: PeerAdvertiserEventProducer) {
        self.session = session
        self.eventProducer = eventProducer
        advertiser = MCNearbyServiceAdvertiser(peer: session.peer.peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = eventProducer
    }
    
    internal func startAdvertising() {
        advertiser.delegate = eventProducer
        advertiser.startAdvertisingPeer()
    }
    
    internal func stopAdvertising() {
        advertiser.stopAdvertisingPeer()
        advertiser.delegate = nil
    }
}
