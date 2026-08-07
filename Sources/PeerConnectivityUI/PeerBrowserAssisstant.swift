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
import ObjectiveC
import UIKit

fileprivate var PeerBrowserViewControllerEventProducerKey : UInt8 = 0

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
        let browserViewController = MCBrowserViewController(serviceType: serviceType, session: session)
        browserViewController.delegate = eventProducer
        objc_setAssociatedObject(
            browserViewController,
            &PeerBrowserViewControllerEventProducerKey,
            eventProducer,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return browserViewController
    }
}
#endif
