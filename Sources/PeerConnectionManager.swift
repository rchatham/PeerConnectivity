//
//  PeerConnectionManager.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

/// The service type describing the channel over which connections are made.
public typealias ServiceType = String

/// Struct representing specified keys for configuring a connection manager.
public struct PeerConnectivityKeys {
    static fileprivate let CertificateListener = "CertificateRecievedListener"
}

/// Enum represeting available connection types. `.automatic`, `.inviteOnly`, `.custom`.
public enum PeerConnectionType: Int {

    /// Connection type where all available devices attempt to connect automatically.
    case automatic = 0

    /// Connection type providing the browser view controller and advertiser assistant
    /// giving the user the ability to handle connections with nearby peers.
    case inviteOnly

    // No default connection implementation is given allowing full control
    //  for determining approval of connections using custom algorithms.
    case custom
}

public enum PeerManagerMode: Int {

    /// use `session` and `advertiser` only, advertise itself and wait for invitation from `browsers`
    case master = 0

    /// use `session` and `browser` only, once connected to an advertiser browsing is disabled
    case slave

    /// use `session` and `advertiser` together similar to `master` mode
    /// However, browser is also started and invite similar node w/ matching 'serviceType'
    /// usig .custom connectionType you can still manage invitation/acceptation
    /// however in this mode browser will instance new `session` for each new node discovered
    case node

}

/// Functional wrapper for Apple's MultipeerConnectivity framework.
///
/// Initialize a PeerConnectionManager to enable mesh-networking over bluetooth and wifi when available.
///  Configure the networking protocol of the session and then start to begin connecting to nearby peers.
public class PeerConnectionManager {
    
    // MARK: - Static Properties -

    /// Access to shared connection managers by their service type.
    public fileprivate(set) static var shared: [ServiceType: PeerConnectionManager] = [:]

    // MARK: - Nested Properties -

    enum Error: Swift.Error {
        case unsupportedModeUsage
        case peerUnavailable
        case serviceAlreadyConnected
        case unknownInvitation
        case maxConnectionRetriesExceeded
    }

    fileprivate static let subServiceKey: String = "subService"

    // MARK: - Properties -

    /// Access to the local peer representing the user.
    public let peer: Peer

    /// The manager mode for the connection manager. instance 'advertiser' or 'assistant' relatively
    public let managerMode: PeerManagerMode

    /// The connection type for the connection manager. (ex. `.automatic`, `.inviteOnly`, `.custom`)
    public let connectionType: PeerConnectionType

    /// an array of [ SecIdentityRef, [ zero or more additional certs ] ].
    public var sessionSecurityIdentity: [Any]? = nil
    public var sessionEncryptionPreference: MCEncryptionPreference = .optional

    // MARK: - Computed Properties -

    /// Returns the peers that are connected on the current session.
    public var connectedPeers: [Peer] {
        return session.connectedPeers
    }

    public var connectedServicePeers: [Peer] {
        return servicesSessions.reduce([], { (peers, serviceSession) -> [Peer] in
            return Array(Set(peers + [serviceSession.servicePeer]))
        })
    }

    public var allAvailableSessions: [PeerSession] {
        return [session] + servicesSessions
    }

    public var allAvailablePeers: [Peer] {
        return servicesSessions.reduce(connectedPeers, { (peers, serviceSession) -> [Peer] in
            return Array(Set(peers + [serviceSession.servicePeer] + serviceSession.connectedPeers))
        })
    }

    /// Nearby peers available for connecting.
    ///
    /// - Note: Can be observed by listening for PeerConnectivityEvent.nearbyPeersChanged(foundPeers:).
    public fileprivate(set) var foundPeers: [Peer] = [] {
        didSet {
            observer.value = .nearbyPeersChanged(foundPeers: foundPeers)
        }
    }

    // MARK: - Private Properties

    /// This will be the `advertiser` session in `.master` and `.none` mode
    /// however it'll be the `browser` session in `.slave` mode
    public let session: PeerSession
    public var servicesSessions: [PeerSession] = []

    fileprivate let serviceType: ServiceType
    fileprivate let subService: ServiceType
    fileprivate let serviceDiscoveryInfo: [String: String]?

    internal var browser: PeerBrowser?
    lazy fileprivate var browserAssisstant: PeerBrowserAssisstant? = {
        return PeerBrowserAssisstant(session: session, serviceType: serviceType,
                                     eventProducer: browserViewControllerEventProducer)
    }()

    fileprivate let advertiser: PeerAdvertiser
    lazy fileprivate var advertiserAssisstant: PeerAdvertiserAssisstant? = {
        return PeerAdvertiserAssisstant(session: session, serviceType: serviceType,
                                        eventProducer: advertiserAssisstantEventProducer)
    }()

    // MARK: - Event Observable Properties

    internal let mutex: Mutex
    internal var retyAttemptQueue: DispatchQueue? = nil

    internal let responder: PeerConnectionResponder
    fileprivate let observer = MultiObservable<PeerConnectionEvent>(.ready)

    fileprivate let sessionObserver = Observable<SessionEventContainer>((nil, .none))
    fileprivate let browserObserver = Observable<PeerBrowserEvent>(.none)
    fileprivate let advertiserObserver = Observable<PeerAdvertiserEvent>(.none)

    /// - Theses are interfaces/encapsulated controllers from apple
    fileprivate let advertiserAssisstantObserver = Observable<PeerAdvertiserAssisstantEvent>(.none)
    fileprivate let browserViewControllerObserver = Observable<PeerBrowserViewControllerEvent>(.none)

    // MARK: - Event Producer Properties

    fileprivate let sessionEventProducer: PeerSessionEventProducer
    fileprivate let browserEventProducer: PeerBrowserEventProducer
    fileprivate let advertiserEventProducer: PeerAdvertiserEventProducer

    fileprivate let advertiserAssisstantEventProducer: PeerAdvertiserAssisstantEventProducer

    fileprivate let browserViewControllerEventProducer: PeerBrowserViewControllerEventProducer

    // MARK: - Initializer -

    /// Initializer for a connection manager. Requires the requested service type.
    ///     If the connectionType and displayName are not specified the connection manager \
    ///     defaults to .Automatic and using the local device name.
    ///
    /// - parameter serviceType: The requested service type describing the channel on which peers are able to connect.
    /// - parameter connectionType: Takes a PeerConnectionType case determining the default behavior of the framework.
    /// - parameter displayName: The local user's display name to other peers.
    ///
    /// - Returns: A fully initialized `PeerConnectionManager`.
    public init(serviceType: ServiceType,
                subService: ServiceType = "",
                displayName: String = UIDevice.current.name,
                serviceDiscoveryInfo: [String: String]? = nil,
                connectionType: PeerConnectionType = .automatic, managerMode: PeerManagerMode = .master,
                securityIdentity identity: [Any]?, encryptionPreference: MCEncryptionPreference) {
        let subServiceDict = [Self.subServiceKey: subService]
        self.serviceDiscoveryInfo = subServiceDict.merging(serviceDiscoveryInfo ?? [:]) { (_, new) in new }

        self.serviceType = serviceType

        self.managerMode = managerMode
        self.connectionType = connectionType

        self.sessionSecurityIdentity = identity
        self.sessionEncryptionPreference = encryptionPreference

        self.peer = Peer(peerID: MCPeerID(displayName: displayName), status: .currentUser,
                         info: self.serviceDiscoveryInfo)
        self.subService = subService

        // - Lock

        do {
            self.mutex = try Mutex()
        } catch {
            fatalError("Mutex initialization failed for PeerConnectivity")
        }

        // - Producers, Observers && Responders

        sessionEventProducer = PeerSessionEventProducer(observer: sessionObserver)
        browserEventProducer = PeerBrowserEventProducer(observer: browserObserver)
        advertiserEventProducer = PeerAdvertiserEventProducer(observer: advertiserObserver)

        advertiserAssisstantEventProducer = PeerAdvertiserAssisstantEventProducer(observer: advertiserAssisstantObserver)
        browserViewControllerEventProducer = PeerBrowserViewControllerEventProducer(observer: browserViewControllerObserver)

        responder = PeerConnectionResponder(observer: observer)

        // - Session, Advertiser, Browser

        session = PeerSession(peer: peer, eventProducer: sessionEventProducer,
                              securityIdentity: sessionSecurityIdentity, encryptionPreference: encryptionPreference)
        advertiser = PeerAdvertiser(session: session, serviceType: serviceType,
                                    discoveryInfo: self.serviceDiscoveryInfo, eventProducer: advertiserEventProducer)

        switch managerMode {
        case .node:
            browser = PeerBrowser(peer: peer, serviceType: serviceType, factory: { (browserPeer, _) -> PeerSession in
                self.disconnectServiceSession(for: browserPeer)
                let nodeServiceSession = PeerSession(peer: self.peer, servicePeer: browserPeer,
                                                     eventProducer: self.sessionEventProducer,
                                                     securityIdentity: self.sessionSecurityIdentity,
                                                     encryptionPreference: self.sessionEncryptionPreference)
                self.servicesSessions += [nodeServiceSession]
                return nodeServiceSession
            }, eventProducer: browserEventProducer)
        case .slave:
            browser = PeerBrowser(session: session, serviceType: serviceType, eventProducer: browserEventProducer)
        default: break
        }

        // - Default responder listener

        // Currently checking security certificates is not yet supported.
        responder.addListener({ (event) in
            switch event {
            case .receivedCertificate(session: _, peer: _, certificate: _, handler: let handler):
                handler(true)
            default: break
            }
        }, forKey: PeerConnectivityKeys.CertificateListener)
        
        // Prevent mingling signals from the same device
        if let existing = PeerConnectionManager.shared[subService] {
            existing.stop()
            existing.removeAllListeners()
        }


        PeerConnectionManager.shared[subService] = self
    }
    
    deinit {
        stop()
        removeAllListeners()
        if let existing = PeerConnectionManager.shared[subService], existing === self {
            PeerConnectionManager.shared.removeValue(forKey: subService)
        }
    }
}

// MARK: - PeerConnectionManager business functions -

extension PeerConnectionManager {

    /// Start the connection manager with optional completion. Calling this initiates browsing and advertising using the specified connection type.
    ///
    /// - parameter completion: Called once session is initialized. Default is `nil`.
    public func start(_ completion: (() -> Void)? = nil) throws {
        self.mutex.lock()
        defer { self.mutex.unlock() }

        configureManagerPeerObservers()
        configureObserverResponseEventDispatch()
        try configureDefaultConnectionTypeBehavior()

        retyAttemptQueue = DispatchQueue(label: "com.peerconnetion.retry-attempt-queue",  qos: .userInitiated,
                                         attributes: .concurrent, autoreleaseFrequency: .workItem)

        session.startSession()
        browser?.startBrowsing()

        advertiser.stopAdvertising()
        advertiser.startAdvertising()
        
        observer.value = .started
        completion?()
    }

    // Refresh the current session.
    // This call disconnects the user from the current session and then restarts the session \
    //  with completion maintaing the current sessions configuration.
    //
    // - parameter completion: Completion handler called after the session has completed refreshing.
    public func refresh(_ completion: (() -> Void)? = nil) throws {
        stop()
        try start(completion)
    }

    /// Stop the current connection manager from listening to delegate callbacks and disconnects from the current session.
    public func stop() {
        self.mutex.lock()
        defer { self.mutex.unlock() }

        retyAttemptQueue?.sync { self.retyAttemptQueue = nil }

        browser?.invitations = []

        session.stopSession()
        servicesSessions.forEach { $0.stopSession() }
        servicesSessions = []

        browser?.stopBrowsing()
        advertiser.stopAdvertising()
        advertiserAssisstant?.stopAdvertisingAssisstant()

        observer.value = .ended

        foundPeers = []
        sessionObserver.observers = []
        browserObserver.observers = []
        advertiserObserver.observers = []
        advertiserAssisstantObserver.observers = []
        browserViewControllerObserver.observers = []

        sessionObserver.value = (nil, .none)
        browserObserver.value = .none
        advertiserObserver.value = .none
        advertiserAssisstantObserver.value = .none
        browserViewControllerObserver.value = .none

        observer.value = .ready
    }

    // MARK: - Private Configurations

    private func updatePeersStatus(_ peer: Peer, session: PeerSession? = nil, status: Peer.Status) {
        let updatedPeer = Peer(peer: peer, status: status)

        foundPeers = foundPeers.map { return $0 === peer ? updatedPeer : $0 }
        servicesSessions = servicesSessions.map({ (serviceSession) in
            guard serviceSession.peer === peer || serviceSession.servicePeer === peer else {
                return serviceSession
            }

            let peer = serviceSession.peer === peer ? updatedPeer : serviceSession.peer
            let servicePeer = serviceSession.servicePeer === peer ? updatedPeer : serviceSession.servicePeer

            return PeerSession(session: serviceSession, peer: peer, servicePeer: servicePeer)
        })
    }

    private func disconnectServiceSession(for peer: Peer) {
        guard let serviceSession = servicesSessions.first(where: { $0.peer == peer || $0.peer === peer }) else {
            return
        }

        disconnectServiceSession(serviceSession)
    }

    private func disconnectServiceSession(_ session: PeerSession) {
        let lostServicesSessions = servicesSessions.filter({ $0 == session })

        lostServicesSessions.forEach({ $0.stopSession() })
        servicesSessions = Array(Set(servicesSessions).subtracting(lostServicesSessions))
    }

    private func devicesConnectionChange(peer: Peer, session: PeerSession) {
        updatePeersStatus(peer, status: peer.status)

        switch peer.status {
        case .connecting where session.isDistantServiceSession == true:
            browser?.updateInvitation(for: peer, status: .connecting)

        case .notConnected where self.session != session && session.isDistantServiceSession == true:
            if foundPeers.firstIndex(of: peer) != nil &&
                browser?.updateInvitation(for: peer, status: .notConnected) == true {
                /// ^ If service still available and we're in the invitation cycle (invitation exist)
                return /// does not propage '.deviceChanged' event while attempting re-connect, only in invitation cycle
            }

            disconnectServiceSession(session)
            updatePeersStatus(peer, status: .unavailable)
            browser?.updateInvitation(for: peer, status: .unavailable)

        default:
            browser?.updateInvitation(for: peer, status: .connected)
        }

        guard session.isDistantServiceSession == false || peer == session.servicePeer else {
            logger.info("\t - distant service slave, other device connection: \(peer)")
            return
        }

        // ignore this because user wants to knows services connecti on events (knows when he's connected to a distant service
        //guard let connectedPeers = self?.connectedPeers else { break }
        observer.value = .devicesChanged(session: session, peer: peer, connectedPeers: connectedPeers)
    }

    private func receivedInvitation(peer: Peer, context: Data?,
                                    invitationHandler: @escaping (Bool, PeerSession) -> Void) {
        let invitationReceiver = { [weak self] (accept: Bool) -> Void in
            guard let session = self?.session else { return }
            invitationHandler(accept, session)
        }

        observer.value = .receivedInvitation(peer: peer, withContext: context, invitationHandler: invitationReceiver)

        /// Inspect if automatic-reconnection to '.unavailable' services works and we don't need to do it manually
        /// see commit #a6ff1cfc511ed94ee2c808bf339cdbf163cc0f0c if needed

        let matchingServicePeer = foundPeers.first(where: { $0.displayName == peer.displayName })
        if let servicePeer = matchingServicePeer, matchingServicePeer?.status == .unavailable {
            /// this resolve services session being reused and thus not rediscovered after small disconnections
            logger.debug("force discovery of matching inviting peer service for distant-service")
            observer.value = .foundPeer(peer: servicePeer, info: servicePeer.serviceDiscoveryInfo)
        }
    }

    /// observe events from multiple observer and dispatch them to a single `observer`
    ///    `browserObserver`, `advertiserObserver`, `sessionObserver` -> `observer` -> `responder`
    private func configureObserverResponseEventDispatch() {
        browserObserver.addObserver { [weak self] event in
            switch event {
            case .foundPeer(let peer, let info):
                self?.observer.value = .foundPeer(peer: peer, info: info)
            case .lostPeer(let peer):
                self?.observer.value = .lostPeer(peer: peer)
            case .didNotStartBrowsingForPeers(let error):
                self?.observer.value = .error(error)
            default: break
            }
        }

        advertiserObserver.addObserver { [weak self] event in
            switch event {
            case.didReceiveInvitationFromPeer(peer: let peer, withContext: let context, invitationHandler: let invite):
                self?.receivedInvitation(peer: peer, context: context, invitationHandler: invite)
            case .didNotStartAdvertisingPeer(let error):
                self?.observer.value = .error(error)
            default: break
            }
        }

        sessionObserver.addObserver { [weak self] eventContainer in
            let event = eventContainer.event
            let matchingSession = self?.servicesSessions.first(where: { $0 == eventContainer.session })

            guard let session = matchingSession ?? eventContainer.session else {
                return
            }

            switch event {
            case .devicesChanged(peer: let peer):
                DispatchQueue.global().async {
                    self?.mutex.lock()
                    defer { self?.mutex.unlock() }

                    self?.devicesConnectionChange(peer: peer, session: session)
                }
            case .didReceiveData(peer: let peer, data: let data):
                self?.observer.value = .receivedData(session: session, peer: peer, data: data)
                guard let eventInfo = NSKeyedUnarchiver.unarchiveObject(with: data) as? [String:Any] else { return }
                self?.observer.value = .receivedEvent(session: session, peer: peer, eventInfo: eventInfo)
            case .didReceiveCertificate(peer: let peer, certificate: let certificate, handler: let handler):
                self?.observer.value = .receivedCertificate(session: session, peer: peer, certificate: certificate, handler: handler)
            case .didReceiveStream(peer: let peer, stream: let stream, name: let name):
                self?.observer.value = .receivedStream(session: session, peer: peer, stream: stream, name: name)
            case .startedReceivingResource(peer: let peer, name: let name, progress: let progress):
                self?.observer.value = .startedReceivingResource(session: session, peer: peer, name: name, progress: progress)
            case .finishedReceivingResource(peer: let peer, name: let name, url: let url, error: let error):
                self?.observer.value = .finishedReceivingResource(session: session, peer: peer, name: name, url: url, error: error)
            default: break
            }
        }
    }

    private func configureManagerPeerObservers() {
        browserObserver.addObserver { [weak self] event in
            DispatchQueue.global().async {
                self?.mutex.lock()
                defer { self?.mutex.unlock() }

                switch event {
                case .foundPeer(let peer, _):
                    guard let peers = self?.foundPeers, !peers.contains(peer) else { break }
                    self?.foundPeers.append(peer)
                case .lostPeer(let peer):
                    self?.updatePeersStatus(peer, status: .unavailable)
                    guard let index = self?.foundPeers.firstIndex(of: peer) else { break }

                    self?.foundPeers.remove(at: index)
                    self?.disconnectServiceSession(for: peer)

                default: break
                }
            }
        }

        /// here we could potentially restart the advertiser in `master` mode (if stopped)
        /// or                        restart the browser in `slave` mode (if stopped)
        /// however restarting everything, i don't really see the point, you've got no-one in your session
        /// isn't an issue if you're still advertising
//        sessionObserver.addObserver { [weak self] event in
//            DispatchQueue.main.async {
//                guard let peerCount = self?.connectedPeers.count,
//                    let peerSession = event.0, peerSession == self?.session else { return }
//
//                switch event.1 {
//                case .devicesChanged(peer: let peer) where peerCount <= 0 :
//                    switch peer.status {
//                    case .notConnected:
//                        try? self?.refresh()
//                    default: break
//                    }
//                default: break
//                }
//            }
//        }
    }

    private func configureDefaultConnectionTypeBehavior() throws {
        switch connectionType {
        case .automatic: // TODO use internal observer instead of individuals producders
            browserObserver.addObserver { [unowned self] event in
                DispatchQueue.main.async {
                    switch event {
                    case .foundPeer(let peer, let discoveryInfo):
                        guard self.subService == discoveryInfo?[Self.subServiceKey] ?? "" else { return }
                        do {
                            try self.invitePeer(peer)
                        } catch {
                            print("[PEER] invite error: \(error)")
                        }
                    default: break
                    }
                }
            }
            advertiserObserver.addObserver { [unowned self] event in
                DispatchQueue.main.async {
                    switch event {
                    case .didReceiveInvitationFromPeer(peer: _, withContext: _, invitationHandler: let handler):
                        handler(true, self.session)
                        self.advertiser.stopAdvertising()
                    default: break
                    }
                }
            }

        case .inviteOnly:
            guard managerMode != .slave else {
                throw Error.unsupportedModeUsage
            }

            advertiserAssisstant?.startAdvertisingAssisstant()

        case .custom: break
        }
    }

    // MARK: - Browser session management

    /// Close session for browsing peers to invite.
    public func closeSession() {
        browser?.stopBrowsing()
    }
    
    /// Open session for browsing peers to invite.
    public func openSession() {
        browser?.startBrowsing()
    }

    // Returns a browser view controller if the connectionType was set to `.InviteOnly` or returns `nil` if not.
    //
    // - parameter callback: Events sent back with cases `.DidFinish` and `.DidCancel`.
    //
    // - Returns: A browser view controller for inviting available peers nearby if connection type is `.InviteOnly` or `nil` otherwise.

    public func browserViewController(_ callback: @escaping (PeerBrowserViewControllerEvent) -> Void) -> UIViewController? {
        browserViewControllerObserver.addObserver { callback($0) }
        switch connectionType {
        case .inviteOnly: return browserAssisstant?.peerBrowserViewController()
        default: return nil
        }
    }

}


