//
//  NetworkPeerTransportAdapters.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import Network

@available(iOS 13.0, macOS 10.15, *)
internal final class NetworkPeerSessionTransport : PeerSessionTransport {

    internal let peer : Peer
    fileprivate let coordinator : NetworkPeerCoordinator<NetworkPeerConnection>
    fileprivate var listener : NetworkPeerListening

    internal var connectedPeers : [Peer] {
        return coordinator.connectedPeers
    }

    internal convenience init(peer: Peer, sessionObserver: Observable<PeerSessionEvent>) {
        let browserObserver = Observable<PeerBrowserEvent>(.none)
        let advertiserObserver = Observable<PeerAdvertiserEvent>(.none)
        self.init(peer: peer,
            sessionObserver: sessionObserver,
            browserObserver: browserObserver,
            advertiserObserver: advertiserObserver)
    }

    internal init(peer: Peer,
        sessionObserver: Observable<PeerSessionEvent>,
        browserObserver: Observable<PeerBrowserEvent>,
        advertiserObserver: Observable<PeerAdvertiserEvent>) {
        self.peer = peer
        let coordinator = NetworkPeerCoordinator<NetworkPeerConnection>(localPeer: peer,
            sessionObserver: sessionObserver,
            browserObserver: browserObserver,
            advertiserObserver: advertiserObserver)
        self.coordinator = coordinator
        self.listener = FailedNetworkPeerListener()
    }

    internal init(peer: Peer,
        coordinator: NetworkPeerCoordinator<NetworkPeerConnection>,
        listener: NetworkPeerListening) {
        self.peer = peer
        self.coordinator = coordinator
        self.listener = listener
    }

    internal func startSession() {
        listener.start()
    }

    internal func configureListener(serviceType: ServiceType) {
        listener = NetworkPeerSessionTransport.makeListener(peer: peer,
            coordinator: coordinator,
            serviceType: serviceType)
    }

    internal func stopSession() {
        listener.cancel()
        coordinator.cancelAllConnections()
    }

    internal func sendData(_ data: Data, toPeers peers: [Peer] = []) {
        coordinator.sendData(data, toPeers: peers)
    }

    internal func sendDataStream(_ streamName: String, toPeer peer: Peer) throws -> OutputStream {
        throw NSError(domain: "PeerConnectivity.NetworkPeerSessionTransport", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Network framework transport does not support data streams yet.",
        ])
    }

    internal func sendResourceAtURL(_ resourceURL: URL,
        withName name: String,
        toPeer peer: Peer,
        withCompletionHandler completion: ((Error?)->Void)?) -> Progress? {
        let error = NSError(domain: "PeerConnectivity.NetworkPeerSessionTransport", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Network framework transport does not support resource transfer yet.",
        ])
        completion?(error)
        return nil
    }

    internal func addInboundConnection(_ connection: NetworkPeerConnection) {
        connection.setDataHandler { [weak self, weak connection] frame in
            guard let connection = connection else { return }
            self?.coordinator.receiveFrame(frame, from: connection)
        }
        coordinator.addPendingConnection(connection, direction: .inbound)
    }

    internal func connect(to endpoint: NWEndpoint) {
        let connection = NetworkPeerConnection(endpoint: endpoint)
        connection.setDataHandler { [weak self, weak connection] frame in
            guard let connection = connection else { return }
            self?.coordinator.receiveFrame(frame, from: connection)
        }
        coordinator.addPendingConnection(connection, direction: .outbound)
        connection.start()
    }

    internal func foundPeer(identity: PeerIdentity) {
        coordinator.foundPeer(identity: identity)
    }

    internal func lostPeer(identity: PeerIdentity) {
        coordinator.lostPeer(identity: identity)
    }

    fileprivate static func makeListener(peer: Peer,
        coordinator: NetworkPeerCoordinator<NetworkPeerConnection>,
        serviceType: ServiceType) -> NetworkPeerListening {
        do {
            return try NetworkPeerListener(serviceType: serviceType, connectionHandler: { connection in
                connection.setDataHandler { [weak coordinator, weak connection] frame in
                    guard let connection = connection else { return }
                    coordinator?.receiveFrame(frame, from: connection)
                }
                coordinator.addPendingConnection(connection, direction: .inbound)
            })
        } catch let error {
            NSLog("%@", "Error creating Network listener for \(peer.displayName): \(error)")
            return FailedNetworkPeerListener()
        }
    }
}

@available(iOS 13.0, macOS 10.15, *)
internal final class NetworkPeerBrowserTransport : PeerBrowserTransport {

    fileprivate let session : NetworkPeerSessionTransport
    fileprivate let browser : NetworkPeerBrowsing
    fileprivate let browserObserver : Observable<PeerBrowserEvent>
    fileprivate var endpointsByIdentity : [PeerIdentity:NWEndpoint] = [:]

    internal convenience init(session: NetworkPeerSessionTransport,
        serviceType: ServiceType,
        browserObserver: Observable<PeerBrowserEvent>) {
        let browser = NetworkPeerBrowser(serviceType: serviceType)
        self.init(session: session,
            browser: browser,
            browserObserver: browserObserver)
        browser.setResultHandler { [weak self] change in
            self?.handleBrowserResultChange(change)
        }
    }

    internal init(session: NetworkPeerSessionTransport,
        browser: NetworkPeerBrowsing,
        browserObserver: Observable<PeerBrowserEvent>) {
        self.session = session
        self.browser = browser
        self.browserObserver = browserObserver
    }

    internal func invitePeer(_ peer: Peer, withContext context: Data? = nil, timeout: TimeInterval = 30) {
        guard let endpoint = endpointsByIdentity[peer.identity] else { return }
        session.connect(to: endpoint)
    }

    internal func startBrowsing() {
        browser.start()
    }

    internal func stopBrowsing() {
        browser.cancel()
        endpointsByIdentity.removeAll()
    }

    internal func handleBrowserResultChange(_ change: NWBrowser.Result.Change) {
        switch change {
        case .added(let result):
            foundEndpoint(result.endpoint)
        case .removed(let result):
            lostEndpoint(result.endpoint)
        default: break
        }
    }

    internal func foundEndpoint(_ endpoint: NWEndpoint) {
        let identity = PeerIdentity(identifier: endpoint.debugDescription, displayName: endpoint.debugDescription)
        endpointsByIdentity[identity] = endpoint
        browserObserver.value = .foundPeer(Peer(identity: identity, status: .notConnected))
    }

    internal func lostEndpoint(_ endpoint: NWEndpoint) {
        let identity = PeerIdentity(identifier: endpoint.debugDescription, displayName: endpoint.debugDescription)
        endpointsByIdentity.removeValue(forKey: identity)
        browserObserver.value = .lostPeer(Peer(identity: identity, status: .notConnected))
    }
}

@available(iOS 13.0, macOS 10.15, *)
internal final class NetworkPeerAdvertiserTransport : PeerAdvertiserTransport {

    fileprivate let session : NetworkPeerSessionTransport

    internal init(session: NetworkPeerSessionTransport,
        serviceType: ServiceType,
        advertiserObserver: Observable<PeerAdvertiserEvent>,
        configureListener: Bool = true) {
        self.session = session
        if configureListener {
            self.session.configureListener(serviceType: serviceType)
        }
    }

    internal func startAdvertising() {}

    internal func stopAdvertising() {}
}

@available(iOS 13.0, macOS 10.15, *)
internal final class NetworkPeerAdvertiserAssisstantTransport : PeerAdvertiserAssisstantTransport {

    internal init() {}

    internal func startAdvertisingAssisstant() {}

    internal func stopAdvertisingAssisstant() {}
}

@available(iOS 13.0, macOS 10.15, *)
internal final class FailedNetworkPeerListener : NetworkPeerListening {
    internal func start() {}

    internal func cancel() {}
}
