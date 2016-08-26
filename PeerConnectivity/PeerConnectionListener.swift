//
//  PeerConnectionListener.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/25/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

/**
 Network events that can be responded to via PeerConnectivity.
 */
public enum PeerConnectionEvent {
    case Ready
    case Started
    case DevicesChanged(peer: Peer, connectedPeers: [Peer])
    case ReceivedData(peer: Peer, data: NSData)
    case ReceivedEvent(peer: Peer, event: [String:AnyObject])
    case ReceivedStream(peer: Peer, stream: NSStream, name: String)
    case StartedReceivingResource(peer: Peer, name: String, progress: NSProgress)
    case FinishedReceivingResource(peer: Peer, name: String, url: NSURL, error: NSError?)
    case ReceivedCertificate(peer: Peer, certificate: [AnyObject]?, handler: (Bool)->Void)
    case Error(PeerConnectionError)
    case Ended
    case FoundPeer(peer: Peer)
    case LostPeer(peer: Peer)
    case ReceivedInvitation(peer: Peer, withContext: NSData?, invitationHandler: (Bool)->Void)
}

/**
 Error reporting for PeerConnectivity.
 */
public enum PeerConnectionError : ErrorType {
    case Error(NSError)
    case DidNotStartAdvertisingPeer(NSError)
    case DidNotStartBrowsingForPeers(NSError)
}

/**
 Listener for responding to `PeerConnectionEvent`s.
 */
public typealias PeerConnectionEventListener = PeerConnectionEvent->Void

// TODO: Should this be a class or a struct?
internal class PeerConnectionResponder {
    
    private let peerEventObserver : MultiObservable<PeerConnectionEvent>
    
    internal private(set) var listeners : [String:PeerConnectionEventListener] = [:]
    
    internal init(observer: MultiObservable<PeerConnectionEvent>) {
        peerEventObserver = observer
    }
    
    internal func addListener(listener: PeerConnectionEventListener, performListenerInBackground background: Bool = false, forKey key: String) -> PeerConnectionResponder {
        listeners[key] = listener
        peerEventObserver.addObserver(listener, key: key)
        return self
    }
    
    internal func addListeners(listeners: [String:PeerConnectionEventListener]) -> PeerConnectionResponder {
        listeners.forEach { addListener($0.1, forKey: $0.0) }
        return self
    }
    
    internal func removeAllListeners() {
        listeners = [:]
        peerEventObserver.observers = [:]
    }
    
    internal func removeListenerForKey(key: String) {
        listeners.removeValueForKey(key)
        peerEventObserver.observers.removeValueForKey(key)
    }
}