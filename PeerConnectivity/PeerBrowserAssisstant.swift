//
//  PeerBrowserViewController.swift
//  GameController
//
//  Created by Reid Chatham on 12/24/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal struct PeerBrowserAssisstant {
    
    private let session : PeerSession
    private let serviceType : ServiceType
    private let eventProducer: PeerBrowserViewControllerEventProducer
    
    internal init(session: PeerSession, serviceType: ServiceType, eventProducer: PeerBrowserViewControllerEventProducer) {
        self.session = session
        self.serviceType = serviceType
        self.eventProducer = eventProducer
    }
    
    internal func peerBrowserViewController() -> MCBrowserViewController {
        let bvc = MCBrowserViewController(serviceType: serviceType, session: session.session)
        bvc.delegate = eventProducer
        return bvc
    }
}