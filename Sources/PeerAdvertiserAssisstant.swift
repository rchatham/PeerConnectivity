//
//  PeerAdvertiserAssisstant.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal struct PeerAdvertiserAssisstant : PeerAdvertiserAssisstantTransport {
    
    fileprivate let session : MultipeerSessionTransport
    fileprivate let assisstant : MCAdvertiserAssistant
    internal let discoveryInfo : PeerDiscoveryInfo?
    fileprivate let eventProducer : PeerAdvertiserAssisstantEventProducer?
    
    internal init(session: MultipeerSessionTransport,
                  serviceType: ServiceType,
                  discoveryInfo: PeerDiscoveryInfo? = nil,
                  eventProducer: PeerAdvertiserAssisstantEventProducer? = nil) {
        self.session = session
        self.discoveryInfo = discoveryInfo
        self.eventProducer = eventProducer
        assisstant = MCAdvertiserAssistant(serviceType: serviceType,
                                           discoveryInfo: discoveryInfo,
                                           session: session.multipeerSession)
        if let eventProducer = eventProducer { assisstant.delegate = eventProducer }
    }
    
    internal func startAdvertisingAssisstant() {
        if let eventProducer = eventProducer { assisstant.delegate = eventProducer }
        assisstant.start()
    }
    
    internal func stopAdvertisingAssisstant() {
        assisstant.stop()
        assisstant.delegate = nil
    }
}
