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
    /// Event sent when the `PeerConnectionManager` is ready to start.
    case Ready
    /// Signals the `PeerConnectionManager` was started succesfully.
    case Started
    /// Devices changed event which returns the `Peer` that changed along with the connected `Peer`s. Check the passed `Peer`'s `Status` to see what changed.
    case DevicesChanged(peer: Peer, connectedPeers: [Peer])
    /// Data received from `Peer`.
    case ReceivedData(peer: Peer, data: NSData)
    /// Event received from `Peer`.
    case ReceivedEvent(peer: Peer, event: [String:AnyObject])
    /// Data stream received from `Peer`.
    case ReceivedStream(peer: Peer, stream: NSStream, name: String)
    /// Started receiving a resource from `Peer` with name and `NSProgress`.
    case StartedReceivingResource(peer: Peer, name: String, progress: NSProgress)
    /// Finished receiving resource from `Peer` with name at url with optional error.
    case FinishedReceivingResource(peer: Peer, name: String, url: NSURL, error: NSError?)
    /// Received security certificate from `Peer` with handler.
    case ReceivedCertificate(peer: Peer, certificate: [AnyObject]?, handler: (Bool)->Void)
    /// Received a `PeerConnectionError`.
    case Error(PeerConnectionError)
    /// `PeerConnectionManager` was succesfully stopped.
    case Ended
    /// Found nearby `Peer`.
    case FoundPeer(peer: Peer)
    /// Lost nearby `Peer`.
    case LostPeer(peer: Peer)
    /// Received invitation from `Peer` with optional context data and invitation handler.
    case ReceivedInvitation(peer: Peer, withContext: NSData?, invitationHandler: (Bool)->Void)
}

/**
 Error reporting for PeerConnectivity.
 */
public enum PeerConnectionError : ErrorType {
    /// Non-specific error passed down from Apple's MultipeerConnectivity framework.
    case Error(NSError)
    /// The connection manager failed to begin advertising the local user.
    case DidNotStartAdvertisingPeer(NSError)
    /// The connection manager failed to start browsing for nearby users.
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