//
//  Invitation.swift
//  PeerConnectivity
//
//  Created by Julien Di Marco on 10/12/2018.
//  Copyright © 2018 Reid Chatham. All rights reserved.
//

import Foundation

// MARK: - Invitation Constant && Types -

public enum InvitationError: Swift.Error {
    case invitationPending
    case connectionInconsistency
    case maxConnectionRetriesExceeded
}

// MARK: - Main Invitation Definition -

internal struct Invitation {

    // MARK: - Constants && Types

    static let maxConnectionRetries = 3
    static let maxInconsistentConnectionRetries = 1

    public enum Status {
        /// Invitation was initialized, a `PeerBrowser` might have called `invitedPeer`
        case unknown

        /// `PeerBrowser` called `invitePeer` and `Session` received `.connecting`
        case pending

        /// Invitation failed, `Session` received `.notConnected`, retry count is increment
        case failed

        /// Invitation failed without becoming '.pending', retryCount is reset
        case inconsistent
    }

    // MARK: - Properties

    internal let peer: Peer
    internal let session: PeerSession

    internal var context: Data?
    internal var retryCount: Int = 0
    internal var status: Status = .unknown

    // MARK: - Initializers

    init(peer: Peer, session: PeerSession, context: Data? = nil, retryCount: Int = 0) {
        self.peer = peer
        self.session = session

        self.context = context
        self.retryCount = retryCount
    }

    init(_ invitation: Invitation, status: Status, session: PeerSession? = nil, context: Data? = nil) throws {
        self.peer = invitation.peer
        self.session = session ?? invitation.session
        self.context = context ?? invitation.context

        switch status {
        case .inconsistent:
            self.status = .inconsistent
            self.retryCount = (invitation.status == .inconsistent) ? invitation.retryCount + 1 : 0

            guard invitation.retryCount < Invitation.maxInconsistentConnectionRetries else {
                throw InvitationError.maxConnectionRetriesExceeded
            }

        case .failed:
            guard invitation.status == .pending else {
                throw InvitationError.connectionInconsistency
            }

            guard invitation.retryCount < Invitation.maxConnectionRetries else {
                throw InvitationError.maxConnectionRetriesExceeded
            }

            self.status = status
            self.retryCount = invitation.retryCount + 1

        default:
            self.status = status
            self.retryCount = invitation.retryCount
        }
    }

}

// MARK: - Protocols
// MARK: - Equatable

extension Invitation: Equatable {

    public static func == (lhs: Invitation, rhs: Invitation) -> Bool {
        return lhs.peer == rhs.peer
    }

    public static func == (lhs: Invitation, rhs: Peer) -> Bool {
        return lhs.peer == rhs
    }

}

// MARK: - CustomStringConvertible, CustomDebugStringConvertible

extension Invitation: CustomStringConvertible, CustomDebugStringConvertible {

    public var description: String {
        return debugDescription
    }

    public var debugDescription: String {
        let peerAddress = String(addressHeap(peer.peerID), radix: 16, uppercase: false)
        let sessionAddress = String(addressHeap(session.session), radix: 16, uppercase: false)

        return "<<\(type(of: self))> status: \(status); retryCount: \(retryCount); "
            + "peer: 0x\(peerAddress); session: 0x\(sessionAddress)>"
    }
}

// MARK: - Serialization helper -

internal extension Data {

    var jsonDictionary: [String: Any]? {
        return (try? JSONSerialization.jsonObject(with: self, options: .allowFragments)) as? [String: Any]
    }

}

