//
//  PeerBrowserViewController.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/24/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import PeerConnectivity
#if canImport(UIKit)
import UIKit

internal final class PeerBrowserViewController: MCBrowserViewController {

    fileprivate let eventProducer: PeerBrowserViewControllerEventProducer

    internal init(serviceType: ServiceType, session: MCSession, eventProducer: PeerBrowserViewControllerEventProducer) {
        self.eventProducer = eventProducer
        super.init(serviceType: serviceType, session: session)
        delegate = eventProducer
    }

    @available(*, unavailable)
    required internal init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

internal struct PeerBrowserAssisstant {

    fileprivate let session : MCSession
    fileprivate let serviceType : ServiceType

    internal init(session: MCSession, serviceType: ServiceType) {
        self.session = session
        self.serviceType = serviceType
    }

    internal func peerBrowserViewController(_ callback: @escaping (PeerBrowserViewControllerEvent) -> Void,
                                            peerFilter: PeerBrowserViewControllerPeerFilter? = nil) -> MCBrowserViewController {
        let eventProducer = PeerBrowserViewControllerEventProducer(callback: callback, peerFilter: peerFilter)
        return PeerBrowserViewController(serviceType: serviceType, session: session, eventProducer: eventProducer)
    }
}
#endif
