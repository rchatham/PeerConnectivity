//
//  PeerConnectionResponder.swift
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
    /** 
     Event sent when the `PeerConnectionManager` is ready to start.
     */
    case ready
    /**
     Signals the `PeerConnectionManager` was started succesfully.
     */
    case started
    /**
     Devices changed event which returns the `Peer` that changed along with the connected `Peer`s. Check the passed `Peer`'s `Status` to see what changed.
     */
    case devicesChanged(peer: Peer, connectedPeers: [Peer])
    /**
     Data received from `Peer`.
     */
    case receivedData(peer: Peer, data: Data)
    /**
     Event received from `Peer`.
     */
    case receivedEvent(peer: Peer, eventInfo: [String:AnyObject])
    /**
     Data stream received from `Peer`.
     */
    case receivedStream(peer: Peer, stream: Stream, name: String)
    /**
     Started receiving a resource from `Peer` with name and `NSProgress`.
     */
    case startedReceivingResource(peer: Peer, name: String, progress: Progress)
    /**
     Finished receiving resource from `Peer` with name at url with optional error.
     */
    case finishedReceivingResource(peer: Peer, name: String, url: URL, error: Error?)
    /**
     Received security certificate from `Peer` with handler.
     */
    case receivedCertificate(peer: Peer, certificate: [Any]?, handler: (Bool)->Void)
    /**
     Received a `PeerConnectionError`.
     */
    case error(PeerConnectionError)
    /**
     `PeerConnectionManager` was succesfully stopped.
     */
    case ended
    /**
     Found nearby `Peer`.
     */
    case foundPeer(peer: Peer)
    /**
     Lost nearby `Peer`.
     */
    case lostPeer(peer: Peer)
    /**
     Received invitation from `Peer` with optional context data and invitation handler.
     */
    case receivedInvitation(peer: Peer, withContext: Data?, invitationHandler: (Bool)->Void)
}

/**
 Error reporting for PeerConnectivity.
 */
public enum PeerConnectionError : Error {
    /**
     Non-specific error passed down from Apple's MultipeerConnectivity framework.
     */
    case error(NSError)
    /**
     The connection manager failed to begin advertising the local user.
     */
    case didNotStartAdvertisingPeer(NSError)
    /**
     The connection manager failed to start browsing for nearby users.
     */
    case didNotStartBrowsingForPeers(NSError)
}

/**
 Listener for responding to `PeerConnectionEvent`s.
 */
public typealias PeerConnectionEventListener = (PeerConnectionEvent)->Void

// TODO: Should this be a class or a struct?
internal class PeerConnectionResponder {
    
    fileprivate let peerEventObserver : MultiObservable<PeerConnectionEvent>
    
    internal fileprivate(set) var listeners : [String:PeerConnectionEventListener] = [:]
    
    internal init(observer: MultiObservable<PeerConnectionEvent>) {
        peerEventObserver = observer
    }
    
    @discardableResult internal func addListener(_ listener: @escaping PeerConnectionEventListener, forKey key: String) -> PeerConnectionResponder {
        listeners[key] = listener
        peerEventObserver.addObserver(listener, key: key)
        return self
    }
    
    @discardableResult internal func addListeners(_ listeners: [String:PeerConnectionEventListener]) -> PeerConnectionResponder {
        listeners.forEach { addListener($0.1, forKey: $0.0) }
        return self
    }
    
    internal func removeAllListeners() {
        listeners = [:]
        peerEventObserver.observers = [:]
    }
    
    internal func removeListenerForKey(_ key: String) {
        listeners.removeValue(forKey: key)
        peerEventObserver.observers.removeValue(forKey: key)
    }
}
