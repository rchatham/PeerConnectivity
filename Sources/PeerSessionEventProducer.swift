//
//  PeerSessionEventProducer.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

// MARK: = PeerSession EventProducer Constants && Types -

internal enum PeerSessionEvent {
    case none
    case devicesChanged(peer: Peer)
    case didReceiveData(peer: Peer, data: Data)
    case didReceiveStream(peer: Peer, stream: Stream, name: String)
    case startedReceivingResource(peer: Peer, name: String, progress: Progress)
    case finishedReceivingResource(peer: Peer, name: String, url: URL?, error: Error?)
    case didReceiveCertificate(peer: Peer, certificate: [Any]?, handler: (Bool) -> Void)
}

typealias SessionEventContainer = (session: PeerSession?, event: PeerSessionEvent)

internal class PeerSessionEventProducer: NSObject {
    
    fileprivate let observer : Observable<SessionEventContainer>
    
    internal init(observer: Observable<SessionEventContainer>) {
        self.observer = observer
    }
}

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

// MAKRK: - PeerSession EventProducer -

extension PeerSessionEventProducer: MCSessionDelegate {

    internal func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        NSLog("%@", "peer \(peerID) didChangeState: \(state.stringValue())")
        
        let peer: Peer = Peer(peerID: peerID, status: Peer.Status(state: state))
        let event: PeerSessionEvent = .devicesChanged(peer: peer)
        let peerSession: PeerSession = PeerSession(session: session, sessionPeerStatus: .connected)

        self.observer.value = (peerSession, event)
    }
    
    internal func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        NSLog("%@", "didReceiveData")
        
        let peer = Peer(peerID: peerID, status: .connected)
        let event: PeerSessionEvent = .didReceiveData(peer: peer, data: data)
        let peerSession: PeerSession = PeerSession(session: session, sessionPeerStatus: .connected)

        self.observer.value = (peerSession, event)
    }
    
    internal func session(_ session: MCSession, didReceive stream: InputStream,
                          withName streamName: String, fromPeer peerID: MCPeerID) {
        NSLog("%@", "didReceiveStream")
        
        let peer = Peer(peerID: peerID, status: .connected)
        let event: PeerSessionEvent = .didReceiveStream(peer: peer, stream: stream, name: streamName)
        let peerSession: PeerSession = PeerSession(session: session, sessionPeerStatus: .connected)

        self.observer.value = (peerSession, event)
    }
    
    internal func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                          fromPeer peerID: MCPeerID, with progress: Progress) {
        NSLog("%@", "didStartReceivingResourceWithName")
        
        let peer = Peer(peerID: peerID, status: .connected)
        let event: PeerSessionEvent = .startedReceivingResource(peer: peer, name: resourceName, progress: progress)
        let peerSession: PeerSession = PeerSession(session: session, sessionPeerStatus: .connected)

        self.observer.value = (peerSession, event)
    }
    
    internal func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                          fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        NSLog("%@", "didFinishReceivingResourceWithName")
        
        let peer = Peer(peerID: peerID, status: .connected)
        let event: PeerSessionEvent = .finishedReceivingResource(peer: peer, name: resourceName,
                                                                 url: localURL, error: error)
        let peerSession: PeerSession = PeerSession(session: session, sessionPeerStatus: .connected)

        self.observer.value = (peerSession, event)
    }
    
    internal func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?,
                          fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        NSLog("%@", "didReceiveCertificate")
        
        let peer = Peer(peerID: peerID, status: .connected)
        let event: PeerSessionEvent = .didReceiveCertificate(peer: peer, certificate: certificate, handler: certificateHandler)
        let peerSession: PeerSession = PeerSession(session: session, sessionPeerStatus: .connected)

        self.observer.value = (peerSession, event)
    }

}
