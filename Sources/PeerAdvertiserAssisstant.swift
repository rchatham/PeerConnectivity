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
    
    fileprivate let session : PeerSessionTransport
    fileprivate let assisstant : MCAdvertiserAssistant
    fileprivate let eventProducer : PeerAdvertiserAssisstantEventProducer?
    
    internal init(session: PeerSessionTransport, serviceType: ServiceType, eventProducer: PeerAdvertiserAssisstantEventProducer? = nil) {
        self.session = session
        self.eventProducer = eventProducer
        assisstant = MCAdvertiserAssistant(serviceType: serviceType, discoveryInfo: nil, session: session.multipeerSession)
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
