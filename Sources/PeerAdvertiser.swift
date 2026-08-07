//
//  PeerAdvertiser.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal struct PeerAdvertiser {
    
    fileprivate let session : PeerSession
    fileprivate let advertiser : MCNearbyServiceAdvertiser
    internal let discoveryInfo : PeerDiscoveryInfo?
    fileprivate let eventProducer : PeerAdvertiserEventProducer
    
    internal init(session: PeerSession,
                  serviceType: ServiceType,
                  discoveryInfo: PeerDiscoveryInfo? = nil,
                  eventProducer: PeerAdvertiserEventProducer) {
        self.session = session
        self.discoveryInfo = discoveryInfo
        self.eventProducer = eventProducer
        advertiser = MCNearbyServiceAdvertiser(peer: session.peer.peerID,
                                               discoveryInfo: discoveryInfo,
                                               serviceType: serviceType)
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
