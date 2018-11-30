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

internal struct Invitation {

    // MARK: - Constants && Types

    static let maxConnectionRetries = 3

    // MARK: - Properties

    internal let peer: Peer
    internal let session: PeerSession

    internal var context: Data?
    internal var retryCount: Int = 0

    // MARK: - Initializers

    init(peer: Peer, session: PeerSession, context: Data? = nil, retryCount: Int = 0) {
        self.peer = peer
        self.session = session

        self.context = context
        self.retryCount = retryCount
    }

}

extension Invitation: Equatable {

    public static func == (lhs: Invitation, rhs: Invitation) -> Bool {
        return lhs.peer == rhs.peer
    }

    public static func == (lhs: Invitation, rhs: Peer) -> Bool {
        return lhs.peer == rhs
    }

}


internal struct PeerBrowser {

    // MARK: - Properties -

    fileprivate let peer: Peer?
    fileprivate let session: PeerSession?

    fileprivate var browser: MCNearbyServiceBrowser
    fileprivate let eventProducer: PeerBrowserEventProducer
    fileprivate let sessionFactory: SessionFactory?

    internal var invitations: [Invitation] = []

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

    internal func invitation(for peer: Peer) -> (Int, Invitation)? {
        guard let invitation = invitations.first(where: { $0 == peer }),
            let index = invitations.firstIndex(of: invitation) else {
                return nil
        }

        return (index, invitation)
    }

    internal mutating func invitePeer(invitation: Invitation, context: Data? = nil, timeout: TimeInterval = 30) throws {
        var invitation = invitation // TODO: Check that connection of peer entered 'connecting' before retry connection
        guard let index = invitations.firstIndex(of: invitation) else {
            throw PeerConnectionManager.Error.unknownInvitation
        }

        guard invitation.retryCount < Invitation.maxConnectionRetries else {
            invitations.remove(at: index)
            throw PeerConnectionManager.Error.maxConnectionRetriesExceeded
        }

        invitation.retryCount += 1
        invitation.context = context ?? invitation.context
        invitations[index] = invitation

        let invitationPeer = invitation.peer
        let invitationSession = invitation.session
        let invitationContext = invitation.context

        browser.invitePeer(invitationPeer.peerID, to: invitationSession.session,
                           withContext: invitationContext, timeout: timeout)

        var contextValue: [String: Any]? = nil
        if let context = context {
            contextValue = (try? JSONSerialization.jsonObject(with: context, options: .allowFragments)) as? [String: Any]
        }
        NSLog("%@", "peer invited \(invitationPeer.peerID), retry: \(invitation.retryCount), " +
                    "session: \(invitationSession), context: \(contextValue ?? [:])")
    }

    internal mutating func invitePeer(_ peer: Peer, session: PeerSession? = nil,
                                      withContext context: Data? = nil, timeout: TimeInterval = 30) throws {
        if var invitation = invitations.first(where: { $0 == peer && $0.peer === peer }) {
            try invitePeer(invitation: invitation, context: context, timeout: timeout)
            return
        }

        guard let session = self.session ?? session ?? sessionFactory?(peer, context) else {
            throw PeerConnectionManager.Error.unsupportedModeUsage
        }

        let invitation = Invitation(peer: peer, session: session, context: context)
        invitations.append(invitation)
        browser.invitePeer(peer.peerID, to: session.session, withContext: context, timeout: timeout)

        var contextValue: [String: Any]? = nil
        if let context = context {
            contextValue = (try? JSONSerialization.jsonObject(with: context, options: .allowFragments)) as? [String: Any]
        }
        NSLog("%@", "peer invited \(peer.peerID) session: \(session), context: \(contextValue ?? [:])")
    }

}
