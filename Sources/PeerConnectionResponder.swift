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
    case receivedEvent(peer: Peer, eventInfo: [String:Any])
    /**
     Type-safe message received from `Peer`.

     Decode using:
     ```swift
     if let message = try? JSONDecoder().decode(YourMessageType.self, from: data) {
         // Handle message
     }
     ```

     Or use `observeMessages(ofType:forKey:listener:)` for automatic decoding.
     */
    case receivedMessage(peer: Peer, messageType: String, data: Data)
    /**
     Data stream received from `Peer`.

     This event is MultipeerConnectivity-only and is not emitted by the current Network backend.
     */
    case receivedStream(peer: Peer, stream: Stream, name: String)
    /**
     Started receiving a resource from `Peer` with name and `NSProgress`.

     This event is MultipeerConnectivity-only and is not emitted by the current Network backend.
     */
    case startedReceivingResource(peer: Peer, name: String, progress: Progress)
    /**
     Finished receiving resource from `Peer` with name at url with optional error.

     This event is MultipeerConnectivity-only and is not emitted by the current Network backend.
     */
    case finishedReceivingResource(peer: Peer, name: String, url: URL?, error: Error?)
    /**
     Received security certificate from `Peer` with handler.

     Certificate decisions are handled by `PeerSecurityConfiguration.certificatePolicy`.
     This event is emitted for observation/API compatibility only. Calling the supplied
     handler does not affect the certificate decision.
     */
    case receivedCertificate(peer: Peer, certificate: [Any]?, handler: (Bool)->Void)
    /**
     Received a `PeerConnectionError`.
     */
    case error(Error)
    /**
     `PeerConnectionManager` was succesfully stopped.
     */
    case ended
    /**
     Found nearby `Peer`.
     */
    case foundPeer(peer: Peer)
    /**
     Found nearby `Peer` with advertised discovery metadata.

     Discovery info is public, unauthenticated Bonjour TXT record metadata. Do not treat it as secret
     or trusted without additional validation. Callers with exhaustive switches over
     `PeerConnectionEvent` should handle this case or include a `default` case.
     */
    case foundPeerWithDiscoveryInfo(peer: Peer, discoveryInfo: PeerDiscoveryInfo?)
    /**
     Lost nearby `Peer`.
     */
    case lostPeer(peer: Peer)
    /**
     Nearby peers changed.
     */
    case nearbyPeersChanged(foundPeers: [Peer])
    /**
     Received invitation from `Peer` with optional context data and invitation handler.

     In `.automatic` mode, invitation decisions are handled by `PeerInvitationPolicy`.
     For non-manual automatic policies, this event is emitted for observation/API
     compatibility and the supplied handler does not affect the invitation decision.
     */
    case receivedInvitation(peer: Peer, withContext: Data?, invitationHandler: (Bool)->Void)
}

/**
 Listener for responding to `PeerConnectionEvent`s.
 */
public typealias PeerConnectionEventListener = (PeerConnectionEvent)->Void

internal class PeerConnectionResponder {
    
    fileprivate let peerEventObserver : MultiObservable<PeerConnectionEvent>
    fileprivate let lock = NSLock()
    fileprivate var storedListeners : [String:PeerConnectionEventListener] = [:]
    
    internal fileprivate(set) var listeners : [String:PeerConnectionEventListener] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedListeners
        }
        set {
            lock.lock()
            storedListeners = newValue
            lock.unlock()
        }
    }
    
    internal init(observer: MultiObservable<PeerConnectionEvent>) {
        peerEventObserver = observer
    }
    
    @discardableResult internal func addListener(_ listener: @escaping PeerConnectionEventListener, forKey key: String) -> PeerConnectionResponder {
        lock.lock()
        storedListeners[key] = listener
        lock.unlock()

        peerEventObserver.addObserver(listener, key: key)
        return self
    }
    
    @discardableResult internal func addListeners(_ listeners: [String:PeerConnectionEventListener]) -> PeerConnectionResponder {
        listeners.forEach { addListener($0.1, forKey: $0.0) }
        return self
    }
    
    internal func removeAllListeners() {
        lock.lock()
        storedListeners.removeAll()
        lock.unlock()

        peerEventObserver.removeAllObservers()
    }
    
    internal func removeListenerForKey(_ key: String) {
        lock.lock()
        storedListeners.removeValue(forKey: key)
        lock.unlock()

        peerEventObserver.removeObserverForkey(key)
    }
}
