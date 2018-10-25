//
//  PeerBrowser.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

typealias SessionFactory = (Peer, Data?) -> PeerSession

internal struct PeerBrowser {

    // MARK: - Properties -

    fileprivate let peer: Peer?
    fileprivate let session: PeerSession?

    fileprivate var browser: MCNearbyServiceBrowser
    fileprivate let eventProducer: PeerBrowserEventProducer
    fileprivate let sessionFactory: SessionFactory?

    // MARK: - Initializers -
    
    internal init(session: PeerSession, serviceType: ServiceType, eventProducer: PeerBrowserEventProducer) {
        self.peer = nil
        self.session = session

        self.sessionFactory = nil
        self.eventProducer = eventProducer

        browser = MCNearbyServiceBrowser(peer: session.peer.peerID, serviceType: serviceType)
        browser.delegate = eventProducer
    }

    internal init(peer: Peer, serviceType: ServiceType,
                  factory: @escaping SessionFactory, eventProducer: PeerBrowserEventProducer) {
        self.peer = peer
        self.session = nil

        self.sessionFactory = factory
        self.eventProducer = eventProducer

        browser = MCNearbyServiceBrowser(peer: peer.peerID, serviceType: serviceType)
        browser.delegate = eventProducer
    }

    // MARK: - Browser Management -

    internal func startBrowsing() {
        browser.delegate = eventProducer
        browser.startBrowsingForPeers()
    }

    internal func stopBrowsing() {
        browser.stopBrowsingForPeers()
        browser.delegate = nil
    }

    // MARK: - Browser peer management -

    internal func invitePeer(_ peer: Peer, withContext context: Data? = nil, timeout: TimeInterval = 30) throws {
        guard let session = self.session ?? sessionFactory?(peer, context) else {
            throw PeerConnectionManager.Error.unsupportedModeUsage
        }

        browser.invitePeer(peer.peerID, to: session.session, withContext: context, timeout: timeout)
    }

}
