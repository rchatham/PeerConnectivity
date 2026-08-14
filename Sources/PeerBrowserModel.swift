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
internal struct PeerBrowserModelLifecycleHooks {
    internal let willRegisterListener : ()->Void
    internal let willRemoveListener : ()->Void

    internal init(willRegisterListener: @escaping ()->Void = {},
        willRemoveListener: @escaping ()->Void = {}) {
        self.willRegisterListener = willRegisterListener
        self.willRemoveListener = willRemoveListener
    }
}

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
    fileprivate let lifecycleHooks : PeerBrowserModelLifecycleHooks
    fileprivate var observationRequested = false
    fileprivate var isObserving = false
    fileprivate var observationGeneration = 0
    fileprivate var observationTransition : Task<Void, Never>?

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
    public convenience init(manager: PeerConnectionManager,
        listenerKey: String? = nil,
        peersChanged: PeersChangedHandler? = nil) {
        self.init(manager: manager,
            listenerKey: listenerKey,
            peersChanged: peersChanged,
            lifecycleHooks: PeerBrowserModelLifecycleHooks())
    }

    internal init(manager: PeerConnectionManager,
        listenerKey: String? = nil,
        peersChanged: PeersChangedHandler? = nil,
        lifecycleHooks: PeerBrowserModelLifecycleHooks) {
        self.manager = manager
        self.listenerKey = listenerKey ?? "PeerConnectivity.PeerBrowserModel.\(UUID().uuidString)"
        self.peersChangedHandler = peersChanged
        self.lifecycleHooks = lifecycleHooks
    }

    deinit {
        stopObserving()
    }

    /**
     Starts observing manager discovery and connection events.
     */
    public func startObserving() {
        lock.lock()
        guard !observationRequested else {
            lock.unlock()
            return
        }
        observationRequested = true
        observationGeneration += 1
        let previousTransition = observationTransition
        let manager = self.manager
        let listenerKey = self.listenerKey
        let lifecycleHooks = self.lifecycleHooks
        observationTransition = Task { [weak self] in
            await previousTransition?.value
            lifecycleHooks.willRegisterListener()
            self?.setListenerRegistered(true)
            await manager.listenOnAsync({ [weak self] event in
                self?.handle(event)
            }, performListenerInBackground: true, withKey: listenerKey)
        }
        lock.unlock()
    }

    /**
     Stops observing manager events.
     */
    public func stopObserving() {
        lock.lock()
        guard observationRequested else {
            lock.unlock()
            return
        }
        observationRequested = false
        observationGeneration += 1
        let previousTransition = observationTransition
        let manager = self.manager
        let listenerKey = self.listenerKey
        let lifecycleHooks = self.lifecycleHooks
        observationTransition = Task { [weak self] in
            await previousTransition?.value
            lifecycleHooks.willRemoveListener()
            await manager.removeListenerForKeyAsync(listenerKey)
            self?.setListenerRegistered(false)
        }
        lock.unlock()
    }

    internal func waitForPendingObservationTransition() async {
        await pendingObservationTransition()?.value
    }

    fileprivate func pendingObservationTransition() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return observationTransition
    }

    fileprivate func setListenerRegistered(_ registered: Bool) {
        lock.lock()
        isObserving = registered
        lock.unlock()
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
        guard observationRequested && isObserving else {
            lock.unlock()
            return
        }
        storedDiscoveredPeers = peers.map { peer in
            return storedDiscoveredPeers.first(where: { $0 == peer }) ?? peer
        }
        let handler = peersChangedHandler
        let currentPeers = storedDiscoveredPeers
        let generation = observationGeneration
        notify(handler, peers: currentPeers, generation: generation)
        lock.unlock()
    }

    fileprivate func updatePeers(_ update: (inout [Peer])->Void) {
        lock.lock()
        guard observationRequested && isObserving else {
            lock.unlock()
            return
        }
        update(&storedDiscoveredPeers)
        let handler = peersChangedHandler
        let currentPeers = storedDiscoveredPeers
        let generation = observationGeneration
        notify(handler, peers: currentPeers, generation: generation)
        lock.unlock()
    }

    fileprivate func notify(_ handler: PeersChangedHandler?, peers: [Peer], generation: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let shouldNotify = self.observationRequested && self.isObserving &&
                self.observationGeneration == generation
            self.lock.unlock()
            guard shouldNotify else { return }
            handler?(peers)
        }
    }
}
