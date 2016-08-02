//
//  PeerSessionEventProducer.swift
//  GameController
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal enum PeerSessionEvent {
    case None
    case DevicesChanged(peer: Peer)
    case DidReceiveData(peer: Peer, data: NSData)
    case DidReceiveStream(peer: Peer, stream: NSStream, name: String)
    case StartedReceivingResource(peer: Peer, name: String, progress: NSProgress)
    case FinishedReceivingResource(peer: Peer, name: String, url: NSURL, error: NSError?)
    case DidReceiveCertificate(peer: Peer, certificate: [AnyObject]?, handler: (Bool) -> Void)
}

internal class PeerSessionEventProducer: NSObject {
    
    private let observer : Observable<PeerSessionEvent>
    
    internal init(observer: Observable<PeerSessionEvent>) {
        self.observer = observer
    }
}

extension MCSessionState {
    internal func stringValue() -> String {
        switch(self) {
        case .NotConnected: return "NotConnected"
        case .Connecting: return "Connecting"
        case .Connected: return "Connected"
            //        default: return "Unknown"
        }
    }
}

extension PeerSessionEventProducer: MCSessionDelegate {

    internal func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
        NSLog("%@", "peer \(peerID) didChangeState: \(state.stringValue())")
        
        
        var peer : Peer
        
        switch state {
        case .Connected:
            peer = Peer(peerID: peerID, status: .Connected)
        case .Connecting:
            peer = Peer(peerID: peerID, status: .Connecting)
        case .NotConnected:
            peer = Peer(peerID: peerID, status: .NotConnected)
        }
        
        let event: PeerSessionEvent = .DevicesChanged(peer: peer)
        self.observer.value = event
    }
    
    internal func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
        NSLog("%@", "didReceiveData")
        
        let peer = Peer(peerID: peerID, status: .Connected)
        let event: PeerSessionEvent = .DidReceiveData(peer: peer, data: data)
        self.observer.value = event
    }
    
    internal func session(session: MCSession, didReceiveStream stream: NSInputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        NSLog("%@", "didReceiveStream")
        
        let peer = Peer(peerID: peerID, status: .Connected)
        let event: PeerSessionEvent = .DidReceiveStream(peer: peer, stream: stream, name: streamName)
        self.observer.value = event
    }
    
    internal func session(session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, withProgress progress: NSProgress) {
        NSLog("%@", "didStartReceivingResourceWithName")
        
        let peer = Peer(peerID: peerID, status: .Connected)
        let event: PeerSessionEvent = .StartedReceivingResource(peer: peer, name: resourceName, progress: progress)
        self.observer.value = event
    }
    
    internal func session(session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, atURL localURL: NSURL, withError error: NSError?) {
        NSLog("%@", "didFinishReceivingResourceWithName")
        
        let peer = Peer(peerID: peerID, status: .Connected)
        let event: PeerSessionEvent = .FinishedReceivingResource(peer: peer, name: resourceName, url: localURL, error: error)
        self.observer.value = event
    }
    
    internal func session(session: MCSession, didReceiveCertificate certificate: [AnyObject]?, fromPeer peerID: MCPeerID, certificateHandler: (Bool) -> Void) {
        NSLog("%@", "didReceiveCertificate")
        
        let peer = Peer(peerID: peerID, status: .Connected)
        let event: PeerSessionEvent = .DidReceiveCertificate(peer: peer, certificate: certificate, handler: certificateHandler)
        self.observer.value = event
    }
}
