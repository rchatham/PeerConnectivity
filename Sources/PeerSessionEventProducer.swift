//
//  PeerSessionEventProducer.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

// MARK: - PeerSession EventProducer Constants && Types -

internal enum PeerSessionEvent: CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case devicesChanged(peer: Peer)
    case didReceiveData(peer: Peer, data: Data)
    case didReceiveStream(peer: Peer, stream: Stream, name: String)
    case startedReceivingResource(peer: Peer, name: String, progress: Progress)
    case finishedReceivingResource(peer: Peer, name: String, url: URL?, error: Error?)
    case didReceiveCertificate(peer: Peer, certificate: [Any]?, handler: (Bool) -> Void)

    // MARK: - CustomStringConvertible, CustomDebugStringConvertible

    var description: String {
        switch self {
        case .none: return "none"

        case .devicesChanged(let peer):
            return "devicesChanged(peer: \(peer.peerID), status: \(peer.status))"
        case .didReceiveData(let peer, _):
            return "didReceiveData(peer: \(peer.peerID))"
        case .didReceiveCertificate(let peer, let certificates, _):
            return "didReceiveCertificate(peer: \(peer.peerID), certificates: \(certificates?.count ?? 0))"

        default: return Mirror(reflecting: self).children.first?.label ?? ""
        }
    }

    var debugDescription: String {
        return description
    }

}

typealias SessionEventContainer = (session: PeerSession?, event: PeerSessionEvent)

// MARK: - Session Extensions -

extension MCSessionState {
    internal func stringValue() -> String {
        switch(self) {
        case .notConnected: return "NotConnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
            //        default: return "Unknown"
        }
    }
}

// MARK: - PeerSession EventProducer -

internal class PeerSessionEventProducer: NSObject {

    fileprivate let observer : Observable<SessionEventContainer>

    internal init(observer: Observable<SessionEventContainer>) {
        self.observer = observer
    }

}

extension PeerSessionEventProducer: MCSessionDelegate {

    internal func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peer: Peer = Peer(peerID: peerID, status: Peer.Status(state: state))
        let event: PeerSessionEvent = .devicesChanged(peer: peer)
        let peerSession: PeerSession = PeerSession(session: session, sessionPeerStatus: .connected)

        logger.info("PeerSessionEventProducer - \(event)\n\tsession: \(peerSession)")
        self.observer.value = (peerSession, event)
    }
    
    internal func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let peer = Peer(peerID: peerID, status: .connected)
        let event: PeerSessionEvent = .didReceiveData(peer: peer, data: data)
        let peerSession: PeerSession = PeerSession(session: session, sessionPeerStatus: .connected)

        logger.info("PeerSessionEventProducer - \(event)\n\tsession: \(peerSession)")
        self.observer.value = (peerSession, event)
    }
    
    internal func session(_ session: MCSession, didReceive stream: InputStream,
                          withName streamName: String, fromPeer peerID: MCPeerID) {
        let peer = Peer(peerID: peerID, status: .connected)
        let event: PeerSessionEvent = .didReceiveStream(peer: peer, stream: stream, name: streamName)
        let peerSession: PeerSession = PeerSession(session: session, sessionPeerStatus: .connected)

        logger.info("PeerSessionEventProducer - \(event)\n\tsession: \(peerSession)")
        self.observer.value = (peerSession, event)
    }
    
    internal func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                          fromPeer peerID: MCPeerID, with progress: Progress) {
        let peer = Peer(peerID: peerID, status: .connected)
        let event: PeerSessionEvent = .startedReceivingResource(peer: peer, name: resourceName, progress: progress)
        let peerSession: PeerSession = PeerSession(session: session, sessionPeerStatus: .connected)

        logger.info("PeerSessionEventProducer - \(event)\n\tsession: \(peerSession)")
        self.observer.value = (peerSession, event)
    }
    
    internal func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                          fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        let peer = Peer(peerID: peerID, status: .connected)
        let event: PeerSessionEvent = .finishedReceivingResource(peer: peer, name: resourceName,
                                                                 url: localURL, error: error)
        let peerSession: PeerSession = PeerSession(session: session, sessionPeerStatus: .connected)

        logger.info("PeerSessionEventProducer - \(event)\n\tsession: \(peerSession)")
        self.observer.value = (peerSession, event)
    }
    
    internal func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?,
                          fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        let peer = Peer(peerID: peerID, status: .connected)
        let event: PeerSessionEvent = .didReceiveCertificate(peer: peer, certificate: certificate, handler: certificateHandler)
        let peerSession: PeerSession = PeerSession(session: session, sessionPeerStatus: .connected)

        logger.info("PeerSessionEventProducer - \(event)\n\tsession: \(peerSession)")
        self.observer.value = (peerSession, event)
    }

}
