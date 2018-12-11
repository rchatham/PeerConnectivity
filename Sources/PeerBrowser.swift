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

    // MARK: - Browser Invitation Management -

    internal mutating func updateInvitation(for peer: Peer, status: Peer.Status) -> Bool {
        guard let (index, invitation) = invitation(for: peer), invitation.peer === peer else {
            return false
        }

        switch status {
        case .connecting:
            guard let updatedInvitation = try? Invitation(invitation, status: .pending) else {
                return false
            }

            invitations[index] = updatedInvitation
            logger.info("PeerBrowser Manager - invitation updated - \(updatedInvitation)")

        case .notConnected:
            try? invitePeer(invitation: invitation)

        default:
            invitations.remove(at: index)
            logger.info("PeerBrowser Manager - invitation removed - \(invitation)")
        }

        return true
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

        do {
            let invitation = try Invitation(invitation, status: .failed, context: context)
            invitations[index] = invitation
            logger.info("PeerBrowser Manager - invitation updated - \(invitation)")

            browser.invitePeer(invitation: invitation, timeout: timeout)
            logger.info {
                var contextValue: [String: Any]? = context?.jsonDictionary
                return "peer invited (invitation) \(invitation.peer.peerID), retry: \(invitation.retryCount)" +
                "\n\tsession: \(invitation.session)\n\tcontext: \(contextValue ?? [:])"
            }

        } catch {
            switch error {
            case InvitationError.connectionInconsistency:
                let context = context ?? invitation.context
                guard let session = session ?? sessionFactory?(invitation.peer, context) else {
                    throw PeerConnectionManager.Error.unsupportedModeUsage
                } /// TODO: make sure this session is cleared correctly

                let invitation = try Invitation(invitation, status: .inconsistent, session: session, context: context)
                invitations[index] = invitation
                logger.info("PeerBrowser Manager - invitation changed - \(invitation)")

                browser.invitePeer(invitation: invitation, timeout: timeout)
                logger.info {
                    var contextValue: [String: Any]? = context?.jsonDictionary
                    return "peer invited (new session) \(invitation.peer.peerID), retry: \(invitation.retryCount)" +
                    "\n\tsession: \(invitation.session)\n\tcontext: \(contextValue ?? [:])"
                }

            case InvitationError.maxConnectionRetriesExceeded:
                invitations.remove(at: index)
                logger.info("PeerBrowser Manager - invitation removed - \(invitation)")
                throw PeerConnectionManager.Error.maxConnectionRetriesExceeded

            default: InvitationError.invitationPending
            }
        }
    }

    internal mutating func invitePeer(_ peer: Peer, session: PeerSession? = nil,
                                      withContext context: Data? = nil, timeout: TimeInterval = 30) throws {
        if let invitation = invitations.first(where: { $0 == peer && $0.peer === peer }) {
            guard invitation.status != .pending else {
                throw InvitationError.invitationPending
            }

            /// todo, not sure we need to invite here
            try invitePeer(invitation: invitation, context: context, timeout: timeout)
            return
        }

        guard let session = self.session ?? session ?? sessionFactory?(peer, context) else {
            throw PeerConnectionManager.Error.unsupportedModeUsage
        }

        let invitation = Invitation(peer: peer, session: session, context: context)
        invitations.append(invitation)
        logger.info("PeerBrowser Manager - invitation added - \(invitation)")

        browser.invitePeer(peer.peerID, to: session.session, withContext: context, timeout: timeout)

        logger.info {
            var contextValue: [String: Any]? = context?.jsonDictionary
            return "peer invited \(peer.peerID)\n\tsession: \(session)\n\tcontext: \(contextValue ?? [:])"
        }
    }

}

// MARK: - Multipeer Internals extensions -

extension MCNearbyServiceBrowser {

    func invitePeer(invitation: Invitation, timeout: TimeInterval = 30) {
        invitePeer(invitation.peer.peerID, to: invitation.session.session,
                   withContext: invitation.context, timeout: timeout)
    }

}
