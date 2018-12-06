//
//  PeerConnectionResponder.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/25/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

/// Network events that can be responded to via PeerConnectivity.
public enum PeerConnectionEvent: CustomDebugStringConvertible {

    /// Event sent when the `PeerConnectionManager` is ready to start.
    case ready

    /// Signals the `PeerConnectionManager` was started succesfully.
    case started

    /// `PeerConnectionManager` was succesfully stopped.
    case ended

    /// Received a `PeerConnectionError`.
    case error(Error)

    // - Session peer updates

    /// Devices changed event which returns the `Peer` that changed along with the connected `Peer`s. Check the passed `Peer`'s `Status` to see what changed.
    case devicesChanged(session: PeerSession, peer: Peer, connectedPeers: [Peer])

    // - Advertiser

    /// Received invitation from `Peer` with optional context data and invitation handler.
    case receivedInvitation(peer: Peer, withContext: Data?, invitationHandler: (Bool) -> Void)

    // - Browser Peer/Advertiser discovery

    /// Found nearby `Peer`.
    case foundPeer(peer: Peer, info: DiscoveryInfo?)

    /// Lost nearby `Peer`.
    case lostPeer(peer: Peer)

    /// Nearby peers changed.
    case nearbyPeersChanged(foundPeers: [Peer])

    // - Data Reception

    /// Data received from `Peer`.
    case receivedData(session: PeerSession, peer: Peer, data: Data)

    /// Event received from `Peer`.
    case receivedEvent(session: PeerSession, peer: Peer, eventInfo: [String: Any])

    /// Data stream received from `Peer`.
    case receivedStream(session: PeerSession, peer: Peer, stream: Stream, name: String)

    /// Started receiving a resource from `Peer` with name and `NSProgress`.
    case startedReceivingResource(session: PeerSession, peer: Peer, name: String, progress: Progress)

    /// Finished receiving resource from `Peer` with name at url with optional error.
    case finishedReceivingResource(session: PeerSession, peer: Peer, name: String, url: URL?, error: Error?)

    /// Received security certificate from `Peer` with handler.
    case receivedCertificate(session: PeerSession, peer: Peer, certificate: [Any]?, handler: (Bool) -> Void)

    // MARK: - CustomStringConvertible, CustomDebugStringConvertible

    public var debugDescription: String {
        switch self {
        case .ready: return "ready"
        case .started: return "started - start session, advertiser and browsing"
        case .ended: return "ended - stop session, advertiser and browsing"
        default: return Mirror(reflecting: self).children.first?.label ?? ""
        }
    }

}

/// Listener for responding to `PeerConnectionEvent`s.
public typealias PeerConnectionEventListener = (PeerConnectionEvent) -> Void

internal class PeerConnectionResponder {

    // MARK: - Private Properties -

    fileprivate let peerEventObserver: MultiObservable<PeerConnectionEvent>
    internal fileprivate(set) var listeners: [String: PeerConnectionEventListener] = [:]

    // MARK: - Initializers -

    internal init(observer: MultiObservable<PeerConnectionEvent>) {
        peerEventObserver = observer
    }

    // MARK: - Listener Manipulation Add/Remove -
    
    @discardableResult internal func addListener(_ listener: @escaping PeerConnectionEventListener,
                                                 forKey key: String) -> PeerConnectionResponder {
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
