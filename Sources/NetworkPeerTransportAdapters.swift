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

    internal init(peer: Peer, sessionObserver: Observable<PeerSessionEvent>) {
        self.peer = peer
        let coordinator = NetworkPeerCoordinator<NetworkPeerConnection>(localPeer: peer,
            sessionObserver: sessionObserver)
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

    fileprivate static func makeListener(peer: Peer,
        coordinator: NetworkPeerCoordinator<NetworkPeerConnection>,
        serviceType: ServiceType) -> NetworkPeerListening {
        do {
            return try NetworkPeerListener(serviceType: serviceType, identity: peer.identity, connectionHandler: { connection in
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
    fileprivate let connectToEndpoint : (NWEndpoint) -> Void
    fileprivate let endpointsLock = NSLock()
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
        browserObserver: Observable<PeerBrowserEvent>,
        connectToEndpoint: ((NWEndpoint) -> Void)? = nil) {
        self.session = session
        self.browser = browser
        self.browserObserver = browserObserver
        self.connectToEndpoint = connectToEndpoint ?? { endpoint in session.connect(to: endpoint) }
    }

    internal func invitePeer(_ peer: Peer, withContext context: Data? = nil, timeout: TimeInterval = 30) {
        guard let endpoint = lockedEndpoints({ endpointsByIdentity[peer.identity] }) else { return }
        connectToEndpoint(endpoint)
    }

    internal func startBrowsing() {
        browser.start()
    }

    internal func stopBrowsing() {
        browser.cancel()
        lockedEndpoints { endpointsByIdentity.removeAll() }
    }

    internal func handleBrowserResultChange(_ change: NWBrowser.Result.Change) {
        switch change {
        case .added(let result):
            foundResult(result)
        case .removed(let result):
            lostResult(result)
        default: break
        }
    }

    internal func foundResult(_ result: NWBrowser.Result) {
        guard let identity = identity(from: result) else { return }
        foundEndpoint(result.endpoint, identity: identity)
    }

    internal func lostResult(_ result: NWBrowser.Result) {
        guard let identity = identity(from: result) else { return }
        lostEndpoint(result.endpoint, identity: identity)
    }

    internal func foundEndpoint(_ endpoint: NWEndpoint, identity: PeerIdentity) {
        guard !isLocalIdentity(identity) else { return }
        lockedEndpoints { endpointsByIdentity[identity] = endpoint }
        browserObserver.update(.foundPeer(Peer(identity: identity, status: .notConnected), discoveryInfo: nil))
    }

    internal func lostEndpoint(_ endpoint: NWEndpoint, identity: PeerIdentity) {
        guard !isLocalIdentity(identity) else { return }
        lockedEndpoints { _ = endpointsByIdentity.removeValue(forKey: identity) }
        browserObserver.update(.lostPeer(Peer(identity: identity, status: .notConnected)))
    }

    fileprivate func lockedEndpoints<T>(_ operation: () -> T) -> T {
        endpointsLock.lock()
        defer { endpointsLock.unlock() }
        return operation()
    }

    fileprivate func identity(from result: NWBrowser.Result) -> PeerIdentity? {
        guard case .bonjour(let txtRecord) = result.metadata else { return nil }
        return PeerNetworkDiscoveryInfo(txtRecordDictionary: txtRecord.dictionary)?.identity
    }

    fileprivate func isLocalIdentity(_ identity: PeerIdentity) -> Bool {
        let discoveryIdentity = PeerNetworkDiscoveryInfo(identity: session.peer.identity).identity
        return identity == session.peer.identity || identity == discoveryIdentity
    }
}

@available(iOS 13.0, macOS 10.15, *)
internal final class NetworkPeerAdvertiserTransport : PeerAdvertiserTransport {

    fileprivate let session : NetworkPeerSessionTransport

    internal init(session: NetworkPeerSessionTransport,
        serviceType: ServiceType,
        advertiserObserver _: Observable<PeerAdvertiserEvent>,
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
