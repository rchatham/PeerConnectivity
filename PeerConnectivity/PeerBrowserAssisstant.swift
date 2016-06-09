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
    private let browserViewController : MCBrowserViewController
    private let eventProducer: PeerBrowserViewControllerEventProducer
    
    internal init(session: PeerSession, serviceType: ServiceType, eventProducer: PeerBrowserViewControllerEventProducer) {
        self.session = session
        self.eventProducer = eventProducer
        browserViewController = MCBrowserViewController(serviceType: serviceType, session: session.session)
        browserViewController.delegate = eventProducer
    }
    
    internal func peerBrowserViewController() -> MCBrowserViewController {
        return browserViewController
    }
    
    internal func startBrowsingAssisstant() {
        browserViewController.delegate = eventProducer
    }
    
    internal func stopBrowsingAssistant() {
        browserViewController.delegate = nil
    }
}