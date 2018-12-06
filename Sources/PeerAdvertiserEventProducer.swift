//
//  PeerAdvertiser.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal enum PeerAdvertiserEvent: CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case didNotStartAdvertisingPeer(Error)
    case didReceiveInvitationFromPeer(peer: Peer, withContext: Data?, invitationHandler: (Bool, PeerSession) -> Void)

    // MARK: - CustomStringConvertible, CustomDebugStringConvertible

    var description: String {
        switch self {
        case .none: return "none"
        case .didNotStartAdvertisingPeer(let error):
            return "didNotStartAdvertisingPeer(error: \(error))"

        case .didReceiveInvitationFromPeer(let peer, let context, _):
            var contextDictionary: [String: Any]? = nil
            if let context = context {
                contextDictionary = (try? JSONSerialization.jsonObject(with: context, options: .allowFragments)) as? [String: Any]
            }

            return "didReceiveInvitationFromPeer(peer: \(peer.peerID))\n\tcontext: \(contextDictionary ?? [:])"

        default: return Mirror(reflecting: self).children.first?.label ?? ""
        }
    }

    var debugDescription: String {
        return description
    }

}

internal class PeerAdvertiserEventProducer: NSObject {
    
    fileprivate let observer: Observable<PeerAdvertiserEvent>
    
    internal init(observer: Observable<PeerAdvertiserEvent>) {
        self.observer = observer
    }
}

extension PeerAdvertiserEventProducer: MCNearbyServiceAdvertiserDelegate {

    internal func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let event: PeerAdvertiserEvent = .didNotStartAdvertisingPeer(error)
        logger.error("PeerAdvertiserEventProducer - \(event)")

        self.observer.value = event
    }
    
    internal func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                             withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let handler: ((Bool, PeerSession) -> Void) = { (accept, session) in
            logger.info("\tPeerAdvertiserEventProducer - invitationHandler - accept: \(accept); peer: \(session.peer.peerID)\n\tsession: \(session)")
            invitationHandler(accept, session.session)
        }
        
        let peer = Peer(peerID: peerID, status: .notConnected)
        let event: PeerAdvertiserEvent = .didReceiveInvitationFromPeer(peer: peer, withContext: context,
                                                                       invitationHandler: handler)

        logger.info("PeerAdvertiserEventProducer - \(event)")
        self.observer.value = event
    }

}
