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
    fileprivate let security : PeerConnectionNetworkSecurity
    fileprivate var listener : NetworkPeerListening

    internal var connectedPeers : [Peer] {
        return coordinator.connectedPeers
    }

    internal init(peer: Peer,
        sessionObserver: Observable<PeerSessionEvent>,
        security: PeerConnectionNetworkSecurity = .unauthenticated) {
        self.peer = peer
        var requiresCertificateDecision = false
        if case .certificate = security {
            requiresCertificateDecision = true
        }
        let coordinator = NetworkPeerCoordinator<NetworkPeerConnection>(localPeer: peer,
            sessionObserver: sessionObserver,
            requiresCertificateDecision: requiresCertificateDecision)
        self.coordinator = coordinator
        self.security = security
        self.listener = FailedNetworkPeerListener()
    }

    internal init(peer: Peer,
        coordinator: NetworkPeerCoordinator<NetworkPeerConnection>,
        listener: NetworkPeerListening,
        security: PeerConnectionNetworkSecurity = .unauthenticated) {
        self.peer = peer
        self.coordinator = coordinator
        self.security = security
        self.listener = listener
    }

    internal func startSession() {
        listener.start()
    }

    internal func configureListener(serviceType: ServiceType,
        discoveryInfo: PeerDiscoveryInfo? = nil,
        advertiserObserver: Observable<PeerAdvertiserEvent>? = nil) {
        listener = NetworkPeerSessionTransport.makeListener(peer: peer,
            coordinator: coordinator,
            serviceType: serviceType,
            discoveryInfo: discoveryInfo,
            security: security,
            failureHandler: { error in
                advertiserObserver?.update(.didNotStartAdvertisingPeer(error))
            })
    }

    internal func stopSession() {
        listener.cancel()
        coordinator.cancelAllConnections()
    }

    internal func sendData(_ data: Data, toPeers peers: [Peer] = []) {
        coordinator.sendData(data, toPeers: peers)
    }

    internal func sendData(_ data: Data, toPeers peers: [Peer], completion: @escaping ([Peer:Error]) -> Void) {
        coordinator.sendData(data, toPeers: peers, completion: completion)
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
        configureConnection(connection)
        coordinator.addPendingConnection(connection, direction: .inbound)
    }

    internal func connect(to endpoint: NWEndpoint, invitation: PeerNetworkInvitation = PeerNetworkInvitation()) {
        let connection = NetworkPeerConnection(endpoint: endpoint, security: security)
        configureConnection(connection)
        coordinator.addPendingConnection(connection, direction: .outbound, invitation: invitation)
        connection.start()
    }

    fileprivate func configureConnection(_ connection: NetworkPeerConnection) {
        connection.setDataHandler { [weak self, weak connection] frame in
            guard let connection = connection else { return }
            self?.coordinator.receiveFrame(frame, from: connection)
        }
        connection.setStateHandler { [weak self, weak connection] state in
            guard let connection = connection else { return }
            switch state {
            case .failed, .cancelled:
                self?.coordinator.removeConnection(connection)
            default: break
            }
        }
    }

    fileprivate static func makeListener(peer: Peer,
        coordinator: NetworkPeerCoordinator<NetworkPeerConnection>,
        serviceType: ServiceType,
        discoveryInfo: PeerDiscoveryInfo?,
        security: PeerConnectionNetworkSecurity,
        failureHandler: @escaping (PeerConnectionError) -> Void) -> NetworkPeerListening {
        // Fail closed rather than advertise a record that silently drops caller metadata.
        guard PeerNetworkDiscoveryInfo.isValidAppInfo(discoveryInfo ?? [:]) else {
            return FailedNetworkPeerListener(error: .invalidDiscoveryInfo, failureHandler: failureHandler)
        }
        do {
            return try NetworkPeerListener(serviceType: serviceType,
                identity: peer.identity,
                discoveryInfo: discoveryInfo,
                security: security,
                connectionHandler: { connection in
                connection.setDataHandler { [weak coordinator, weak connection] frame in
                    guard let connection = connection else { return }
                    coordinator?.receiveFrame(frame, from: connection)
                }
                connection.setStateHandler { [weak coordinator, weak connection] state in
                    guard let connection = connection else { return }
                    switch state {
                    case .failed, .cancelled:
                        coordinator?.removeConnection(connection)
                    default: break
                    }
                }
                coordinator.addPendingConnection(connection, direction: .inbound)
            }, stateHandler: { state in
                guard let error = NetworkPeerStateMapping.error(for: state) else { return }
                failureHandler(error)
            })
        } catch let error {
            NSLog("%@", "Error creating Network listener for \(peer.displayName): \(error)")
            return FailedNetworkPeerListener(error: .advertisingFailed(underlying: error),
                failureHandler: failureHandler)
        }
    }
}

@available(iOS 13.0, macOS 10.15, *)
internal final class NetworkPeerBrowserTransport : PeerBrowserTransport {

    fileprivate let session : NetworkPeerSessionTransport
    fileprivate let browser : NetworkPeerBrowsing
    fileprivate let browserObserver : Observable<PeerBrowserEvent>
    fileprivate let connectToEndpoint : (NWEndpoint, PeerNetworkInvitation) -> Void
    fileprivate let maxDiscoveredPeers : Int
    fileprivate let endpointsLock = NSLock()
    fileprivate var endpointsByIdentity : [PeerIdentity:NWEndpoint] = [:]

    internal convenience init(session: NetworkPeerSessionTransport,
        serviceType: ServiceType,
        browserObserver: Observable<PeerBrowserEvent>,
        security: PeerConnectionNetworkSecurity = .unauthenticated) {
        let browser = NetworkPeerBrowser(serviceType: serviceType, security: security)
        self.init(session: session,
            browser: browser,
            browserObserver: browserObserver)
        browser.setResultHandler { [weak self] change in
            self?.handleBrowserResultChange(change)
        }
        browser.setStateHandler { [weak self] state in
            self?.handleBrowserState(state)
        }
    }

    internal init(session: NetworkPeerSessionTransport,
        browser: NetworkPeerBrowsing,
        browserObserver: Observable<PeerBrowserEvent>,
        connectToEndpoint: ((NWEndpoint, PeerNetworkInvitation) -> Void)? = nil,
        maxDiscoveredPeers: Int = NetworkPeerConnectionPolicy().maxDiscoveredPeers) {
        self.session = session
        self.browser = browser
        self.browserObserver = browserObserver
        self.maxDiscoveredPeers = maxDiscoveredPeers
        self.connectToEndpoint = connectToEndpoint ?? { endpoint, invitation in
            session.connect(to: endpoint, invitation: invitation)
        }
    }

    internal func invitePeer(_ peer: Peer, withContext context: Data? = nil, timeout: TimeInterval = 30) {
        guard let endpoint = lockedEndpoints({ endpointsByIdentity[peer.identity] }) else { return }
        connectToEndpoint(endpoint, PeerNetworkInvitation(context: context, timeout: timeout))
    }

    internal func startBrowsing() {
        browser.start()
    }

    internal func stopBrowsing() {
        browser.cancel()
        lockedEndpoints { endpointsByIdentity.removeAll() }
    }

    internal func handleBrowserState(_ state: NWBrowser.State) {
        guard let error = NetworkPeerStateMapping.error(for: state) else { return }
        browserObserver.update(.didNotStartBrowsingForPeers(error))
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
        guard let info = discoveryInfo(from: result) else { return }
        foundEndpoint(result.endpoint, identity: info.identity, discoveryInfo: info.appInfo.isEmpty ? nil : info.appInfo)
    }

    internal func lostResult(_ result: NWBrowser.Result) {
        guard let identity = discoveryInfo(from: result)?.identity else { return }
        lostEndpoint(result.endpoint, identity: identity)
    }

    internal func foundEndpoint(_ endpoint: NWEndpoint, identity: PeerIdentity, discoveryInfo: PeerDiscoveryInfo? = nil) {
        guard Peer.isValidDisplayName(identity.displayName), !isLocalIdentity(identity) else { return }
        let isAdmitted : Bool = lockedEndpoints {
            guard endpointsByIdentity[identity] != nil || endpointsByIdentity.count < maxDiscoveredPeers else {
                return false
            }
            endpointsByIdentity[identity] = endpoint
            return true
        }
        guard isAdmitted else { return }
        browserObserver.update(.foundPeer(Peer(identity: identity, status: .notConnected), discoveryInfo: discoveryInfo))
    }

    internal func lostEndpoint(_ endpoint: NWEndpoint, identity: PeerIdentity) {
        guard Peer.isValidDisplayName(identity.displayName), !isLocalIdentity(identity) else { return }
        let wasTracked = lockedEndpoints { endpointsByIdentity.removeValue(forKey: identity) != nil }
        guard wasTracked else { return }
        browserObserver.update(.lostPeer(Peer(identity: identity, status: .notConnected)))
    }

    fileprivate func lockedEndpoints<T>(_ operation: () -> T) -> T {
        endpointsLock.lock()
        defer { endpointsLock.unlock() }
        return operation()
    }

    fileprivate func discoveryInfo(from result: NWBrowser.Result) -> PeerNetworkDiscoveryInfo? {
        guard case .bonjour(let txtRecord) = result.metadata else { return nil }
        return PeerNetworkDiscoveryInfo(txtRecordDictionary: txtRecord.dictionary)
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
        discoveryInfo: PeerDiscoveryInfo? = nil,
        advertiserObserver: Observable<PeerAdvertiserEvent>,
        configureListener: Bool = true) {
        self.session = session
        if configureListener {
            self.session.configureListener(serviceType: serviceType,
                discoveryInfo: discoveryInfo,
                advertiserObserver: advertiserObserver)
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

    fileprivate let error : PeerConnectionError?
    fileprivate let failureHandler : ((PeerConnectionError) -> Void)?

    /// Reports a listener creation failure when started, after the manager's observers exist.
    internal init(error: PeerConnectionError? = nil,
        failureHandler: ((PeerConnectionError) -> Void)? = nil) {
        self.error = error
        self.failureHandler = failureHandler
    }

    internal func start() {
        guard let error = error else { return }
        failureHandler?(error)
    }

    internal func cancel() {}
}
