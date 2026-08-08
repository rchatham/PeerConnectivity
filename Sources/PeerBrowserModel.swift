//
//  PeerBrowserModel.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

/**
 UIKit-neutral model for app-owned peer selection UI.

 `PeerBrowserModel` observes `.foundPeer`, `.lostPeer`, `.nearbyPeersChanged`, and
 `.devicesChanged` events from a `PeerConnectionManager`, keeps a current discovered
 peer list, and forwards approved selections to `invitePeer`.

 This is intended for `.networkFramework` apps because MultipeerConnectivity's built-in
 browser view controller is not available for Network-backed managers. It can also be
 used with the MultipeerConnectivity backend when an app wants custom peer UI.
 */
public final class PeerBrowserModel {

    /**
     Called after the discovered peer list changes.
     */
    public typealias PeersChangedHandler = ([Peer])->Void

    fileprivate let manager : PeerConnectionManager
    fileprivate let listenerKey : String
    fileprivate let lock = NSLock()
    fileprivate var storedDiscoveredPeers : [Peer] = []
    fileprivate var peersChangedHandler : PeersChangedHandler?
    fileprivate var isObserving = false

    /**
     Current discovered peers in display order.
     */
    public var discoveredPeers : [Peer] {
        lock.lock()
        defer { lock.unlock() }
        return storedDiscoveredPeers
    }

    /**
     Creates a browser model for a connection manager.

     - parameter manager: Connection manager to observe and use for invitations.
     - parameter listenerKey: Listener key used when registering with the manager. When omitted,
       a unique key is generated so multiple models can observe the same manager.
     - parameter peersChanged: Optional callback invoked on the main queue whenever
       `discoveredPeers` changes.
     */
    public init(manager: PeerConnectionManager,
        listenerKey: String? = nil,
        peersChanged: PeersChangedHandler? = nil) {
        self.manager = manager
        self.listenerKey = listenerKey ?? "PeerConnectivity.PeerBrowserModel.\(UUID().uuidString)"
        self.peersChangedHandler = peersChanged
    }

    deinit {
        stopObserving()
    }

    /**
     Starts observing manager discovery and connection events.
     */
    public func startObserving() {
        lock.lock()
        guard !isObserving else {
            lock.unlock()
            return
        }
        isObserving = true
        lock.unlock()

        manager.listenOn({ [weak self] event in
            self?.handle(event)
        }, performListenerInBackground: true, withKey: listenerKey)
    }

    /**
     Stops observing manager events.
     */
    public func stopObserving() {
        lock.lock()
        let shouldRemoveListener = isObserving
        isObserving = false
        lock.unlock()

        guard shouldRemoveListener else { return }
        manager.removeListenerForKey(listenerKey)
    }

    /**
     Invites a discovered peer after app/user approval.

     With `.networkFramework`, `context` and `timeout` are currently ignored by the
     underlying manager.
     */
    public func invitePeer(_ peer: Peer, withContext context: Data? = nil, timeout: TimeInterval = 30) {
        manager.invitePeer(peer, withContext: context, timeout: timeout)
    }

    fileprivate func handle(_ event: PeerConnectionEvent) {
        switch event {
        case .foundPeer(let peer):
            updatePeers { peers in
                guard !peers.contains(peer) else { return }
                peers.append(peer)
            }
        case .lostPeer(let peer):
            updatePeers { peers in
                peers.removeAll { $0 == peer }
            }
        case .nearbyPeersChanged(let foundPeers):
            mergePeers(foundPeers)
        case .devicesChanged(let peer, _):
            updatePeers { peers in
                guard let index = peers.firstIndex(of: peer) else { return }
                peers[index] = peer
            }
        default:
            break
        }
    }

    fileprivate func mergePeers(_ peers: [Peer]) {
        lock.lock()
        storedDiscoveredPeers = peers.map { peer in
            return storedDiscoveredPeers.first(where: { $0 == peer }) ?? peer
        }
        let handler = peersChangedHandler
        let currentPeers = storedDiscoveredPeers
        notify(handler, peers: currentPeers)
        lock.unlock()
    }

    fileprivate func updatePeers(_ update: (inout [Peer])->Void) {
        lock.lock()
        update(&storedDiscoveredPeers)
        let handler = peersChangedHandler
        let currentPeers = storedDiscoveredPeers
        notify(handler, peers: currentPeers)
        lock.unlock()
    }

    fileprivate func notify(_ handler: PeersChangedHandler?, peers: [Peer]) {
        DispatchQueue.main.async {
            handler?(peers)
        }
    }
}
