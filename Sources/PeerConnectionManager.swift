//
//  PeerConnectionManager.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

/**
 The service type describing the channel over which connections are made.

 MultipeerConnectivity service types must be short Bonjour-style identifiers. Use
 `PeerConnectionManager.isValidServiceType(_:)` to validate caller-provided values.
 */
public typealias ServiceType = String

/**
 Discovery metadata advertised over Bonjour TXT records.

 Treat discovery info as public, unauthenticated metadata. Do not include secrets, tokens,
 emails, stable user IDs, or sensitive device information. Prefer non-secret values such as
 protocol versions, capability flags, or non-secret room/session labels.
 */
public typealias PeerDiscoveryInfo = [String:String]

/**
 Struct representing specified keys for configuring a connection manager.
 */
public struct PeerConnectivityKeys {}

// MARK: - Modern Type-Safe Messaging API

/**
 Protocol for type-safe peer-to-peer messages.

 Conform your message types to this protocol to use the modern `sendMessage`/`observeMessages` API
 instead of the legacy `[String:Any]` dictionary-based messaging.

 Example:
 ```swift
 struct ChatMessage: PeerMessage {
     let text: String
     let timestamp: Date
 }
 ```
 */
public protocol PeerMessage: Codable {
    /// Unique identifier for this message type, used for routing on the receiving end.
    static var messageType: String { get }
}

extension PeerMessage {
    /// Default implementation uses the type name as the message type identifier.
    public static var messageType: String {
        return String(describing: Self.self)
    }
}

/**
 Backend implementation used by `PeerConnectionManager`.

 The default backend is `.multipeerConnectivity`, preserving existing runtime behavior.
 The `.networkFramework` backend is an opt-in migration path. It supports Bonjour
 discovery, automatic/custom peer connection, reliable `Data`, and `PeerMessage`
 exchange. MultipeerConnectivity browser UI, data streams, resource transfer, and
 their receive events remain MultipeerConnectivity-only in the current migration.
 Use `networkSecurity: .preSharedKey(_:)` with
 `.networkFramework` to require an authenticated encrypted connection.
 */
public enum PeerConnectionBackend : Equatable {
    /**
     Use Apple's MultipeerConnectivity framework. This is the default backend.
     */
    case multipeerConnectivity
    /**
     Use Apple's Network framework. This backend is experimental and currently supports
     discovery, automatic/custom peer connection, reliable data transport, and
     `PeerMessage` exchange only.
     */
    case networkFramework
}

/**
 Security configuration for Network framework connections.
 */
public enum PeerConnectionNetworkSecurity : Equatable {
    /**
     Use plaintext TCP with no authentication. This mode is available only as migration
     scaffolding and must not be used for sensitive data.
     */
    case unauthenticated
    /**
     Use TLS with a pre-shared key. Peers must be initialized with the same non-empty key
     to connect successfully.
     */
    case preSharedKey(Data)
}

/**
 Enum represeting available connection types. `.automatic`, `.inviteOnly`, `.custom`.
 */
public enum PeerConnectionType : Int {
    /**
     Connection type where all available devices attempt to connect automatically.
     */
    case automatic = 0
    /**
     Connection type providing the browser view controller and advertiser assistant giving the user the ability to handle connections with nearby peers.

     With `.networkFramework`, this mode starts without MultipeerConnectivity UI; use
     `.foundPeer` / `.lostPeer` events and `invitePeer(_:withContext:timeout:)` from app UI.
     */
    case inviteOnly
    /**
     No default connection implementation is given allowing full control for determining approval of connections using custom algorithms.
     */
    case custom
}

fileprivate enum PeerConnectionStartupMode {
    case advertisingAndBrowsing
    case browsingOnly
    case advertisingOnly
}

/**
 Functional wrapper for Apple's MultipeerConnectivity framework.
 
 Initialize a PeerConnectionManager to enable mesh-networking over bluetooth and wifi when available. Configure the networking protocol of the session and then start to begin connecting to nearby peers.
 */
public class PeerConnectionManager {
    
    // MARK: Static
    /**
     Access to shared connection managers by their service type.
     */
    public fileprivate(set) static var shared : [ServiceType:PeerConnectionManager] = [:]

    /**
     Returns whether a service type satisfies MultipeerConnectivity's documented constraints.

     Valid service types are 1 to 15 characters, contain only ASCII lowercase letters,
     numbers, and hyphens, include at least one letter, do not begin or end with a hyphen,
     and do not contain consecutive hyphens. Invalid values may cause
     MultipeerConnectivity objects to fail during initialization.

     - parameter serviceType: Service type string to validate.
     - Returns: `true` when the service type matches the supported format.
     */
    public static func isValidServiceType(_ serviceType: ServiceType) -> Bool {
        guard !serviceType.isEmpty && serviceType.count <= 15 else { return false }
        guard serviceType.first != "-" && serviceType.last != "-" else { return false }
        guard !serviceType.contains("--") else { return false }

        var containsLetter = false
        for scalar in serviceType.unicodeScalars {
            switch scalar.value {
            case 45, 48...57:
                continue
            case 97...122:
                containsLetter = true
            default:
                return false
            }
        }
        return containsLetter
    }
    
    // MARK: Properties
    /**
     The connection type for the connection manager. (ex. `.automatic`, `.inviteOnly`, `.custom`)
     */
    public let connectionType : PeerConnectionType

    /**
     The backend implementation used by this connection manager.

     The default value is `.multipeerConnectivity`. The `.networkFramework` backend is
     opt-in; browser UI, stream/resource sends, and stream/resource receive events remain
     MultipeerConnectivity-only in the current migration.
     */
    public let backend : PeerConnectionBackend

    /**
     Security configuration used by Network framework connections.

     This value is ignored by the MultipeerConnectivity backend.
     */
    public let networkSecurity : PeerConnectionNetworkSecurity
    
    /**
     Access to the local peer representing the user.
     */
    public let peer : Peer

    /**
     Security settings used to create the underlying MultipeerConnectivity session.
     */
    public let securityConfiguration : PeerSecurityConfiguration

    /**
     Public discovery metadata advertised to nearby browsers.

     This metadata is unauthenticated and visible to nearby peers. Do not include secrets,
     tokens, emails, stable user IDs, or sensitive device information.
     */
    public let discoveryInfo : PeerDiscoveryInfo?

    /**
     Policy used to decide whether incoming invitations are accepted in `.automatic` mode.

     Invitation context is unauthenticated metadata received before session establishment.
     Do not treat it as trusted or include raw secrets.
     */
    public let invitationPolicy : PeerInvitationPolicy
    
    /**
     Returns the peers that are connected on the current session.
     */
    public var connectedPeers : [Peer] {
        return session.connectedPeers
    }

    /**
     The MultipeerConnectivity session used by this connection manager, when available.

     Use this property to feature-detect APIs that require MultipeerConnectivity. It returns
     `nil` for the Network framework backend.
     */
    public var availableMultipeerSession : MCSession? {
        return (session as? MultipeerSessionTransport)?.multipeerSession
    }

    /**
     The MultipeerConnectivity session used by this connection manager.

     This is exposed for platform-specific helper packages such as `PeerConnectivityUI`.
     Existing callers retain the original non-optional API and behavior. New code that can
     use the Network framework backend should feature-detect with `availableMultipeerSession`.

     - Warning: Only available when `backend == .multipeerConnectivity`. Accessing this
     property with `.networkFramework` is a programmer error.
     */
    public var multipeerSession : MCSession {
        guard let session = availableMultipeerSession else {
            fatalError("PeerConnectivity: multipeerSession is only available for MultipeerConnectivity transports")
        }
        return session
    }

    /**
     The service type used by this connection manager.

     This is exposed for platform-specific helper packages such as `PeerConnectivityUI`.
     */
    public var peerServiceType : ServiceType {
        return serviceType
    }
    
    /**
     Nearby peers available for connecting. 
     
     - Note: Can be observed by listening for PeerConnectivityEvent.nearbyPeersChanged(foundPeers:).
     */
    public fileprivate(set) var foundPeers: [Peer] = [] {
        didSet {
            emit(.nearbyPeersChanged(foundPeers: foundPeers))
        }
    }
    
    
    // Private
    fileprivate let serviceType : ServiceType
    fileprivate var startupMode : PeerConnectionStartupMode = .advertisingAndBrowsing
    
    fileprivate let observer = Observable<PeerConnectionEvent>(.ready)
    
    fileprivate let sessionObserver = Observable<PeerSessionEvent>(.none)
    fileprivate let browserObserver = Observable<PeerBrowserEvent>(.none)
    fileprivate let advertiserObserver = Observable<PeerAdvertiserEvent>(.none)
    fileprivate let advertiserAssisstantObserver = Observable<PeerAdvertiserAssisstantEvent>(.none)
    
    fileprivate let session : PeerSessionTransport
    fileprivate let browser : PeerBrowserTransport
    fileprivate let advertiser : PeerAdvertiserTransport
    fileprivate let advertiserAssisstant : PeerAdvertiserAssisstantTransport
    fileprivate let transportEventGenerationLock = NSLock()
    fileprivate var transportEventGeneration = 0
    
    fileprivate let responder : PeerConnectionResponder
    
    
    // MARK: Initializer
    /**
     Initializer for a connection manager. Requires the requested service type. If the connectionType and displayName are not specified the connection manager defaults to .Automatic and using the localized host name where available, falling back to the process host name. The `PeerConnectivityUI` product provides an iOS convenience initializer that uses the current device name.
     
     - parameter serviceType: The requested service type describing the channel on which peers are able to connect. Use `isValidServiceType(_:)` to validate caller-provided values before initialization.
     - parameter connectionType: Takes a PeerConnectionType case determining the default behavior of the framework.
     - parameter displayName: The local user's display name to other peers. Display names are visible to nearby peers; empty or overlong values are sanitized to a non-empty maximum of 63 UTF-8 bytes.
     - parameter securityConfiguration: Security settings used to create the underlying MultipeerConnectivity session.
     - parameter discoveryInfo: Public, unauthenticated metadata advertised to nearby browsers.
     - parameter invitationPolicy: Policy used to decide whether incoming invitations are accepted in `.automatic` mode.
     - parameter backend: Backend implementation to use. Defaults to `.multipeerConnectivity`.
     - parameter networkSecurity: Security configuration for `.networkFramework`. Defaults to
       `.unauthenticated` for source compatibility; use `.preSharedKey(_:)` for authenticated
       encrypted Network framework sessions.
     
     - Returns: A fully initialized `PeerConnectionManager`.
     */
    public convenience init(serviceType: ServiceType,
                connectionType: PeerConnectionType = .automatic,
                displayName: String = {
                    #if os(macOS)
                    return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
                    #else
                    return ProcessInfo.processInfo.hostName
                    #endif
                }(),
                securityConfiguration: PeerSecurityConfiguration = .default,
                discoveryInfo: PeerDiscoveryInfo? = nil,
                invitationPolicy: PeerInvitationPolicy = .acceptAll,
                backend: PeerConnectionBackend = .multipeerConnectivity,
                networkSecurity: PeerConnectionNetworkSecurity = .unauthenticated) {
        self.init(serviceType: serviceType,
            connectionType: connectionType,
            displayName: displayName,
            securityConfiguration: securityConfiguration,
            discoveryInfo: discoveryInfo,
            invitationPolicy: invitationPolicy,
            backend: backend,
            networkSecurity: networkSecurity,
            transportFactory: PeerConnectionManager.transportFactory(for: backend, networkSecurity: networkSecurity),
            shouldRegisterSharedManager: true)
    }

    internal convenience init(serviceType: ServiceType,
        connectionType: PeerConnectionType = .automatic,
        displayName: String,
        securityConfiguration: PeerSecurityConfiguration = .default,
        discoveryInfo: PeerDiscoveryInfo? = nil,
        invitationPolicy: PeerInvitationPolicy = .acceptAll,
        backend: PeerConnectionBackend = .multipeerConnectivity,
        networkSecurity: PeerConnectionNetworkSecurity = .unauthenticated,
        transportFactory: PeerConnectionTransportFactory) {
        self.init(serviceType: serviceType,
            connectionType: connectionType,
            displayName: displayName,
            securityConfiguration: securityConfiguration,
            discoveryInfo: discoveryInfo,
            invitationPolicy: invitationPolicy,
            backend: backend,
            networkSecurity: networkSecurity,
            transportFactory: transportFactory,
            shouldRegisterSharedManager: false)
    }

    fileprivate init(serviceType: ServiceType,
        connectionType: PeerConnectionType,
        displayName: String,
        securityConfiguration: PeerSecurityConfiguration,
        discoveryInfo: PeerDiscoveryInfo?,
        invitationPolicy: PeerInvitationPolicy,
        backend: PeerConnectionBackend,
        networkSecurity: PeerConnectionNetworkSecurity,
        transportFactory: PeerConnectionTransportFactory,
        shouldRegisterSharedManager: Bool) {
        self.connectionType = connectionType
        self.backend = backend
        self.networkSecurity = networkSecurity
        self.serviceType = serviceType
        let sanitizedDisplayName = Peer.sanitizedDisplayName(displayName)
        switch backend {
        case .multipeerConnectivity:
            self.peer = Peer(displayName: sanitizedDisplayName)
        case .networkFramework:
            self.peer = Peer(networkDisplayName: sanitizedDisplayName)
        }
        self.securityConfiguration = securityConfiguration
        self.discoveryInfo = discoveryInfo
        self.invitationPolicy = invitationPolicy

        session = transportFactory.makeSession(peer, securityConfiguration, sessionObserver)
        browser = transportFactory.makeBrowser(session, serviceType, browserObserver)
        advertiser = transportFactory.makeAdvertiser(session, serviceType, discoveryInfo, advertiserObserver)
        advertiserAssisstant = transportFactory.makeAdvertiserAssisstant(session,
                                                                         serviceType,
                                                                         discoveryInfo,
                                                                         advertiserAssisstantObserver)

        responder = PeerConnectionResponder(observer: observer)

        guard shouldRegisterSharedManager else { return }
        // Prevent mingling signals from the same device
        if let existing = PeerConnectionManager.shared[serviceType] {
            existing.stop()
            existing.removeAllListeners()
            PeerConnectionManager.shared[serviceType] = self
        }
    }

    deinit {
        stop()
        removeAllListeners()
        if let existing = PeerConnectionManager.shared[serviceType], existing === self {
            PeerConnectionManager.shared.removeValue(forKey: serviceType)
        }
    }

    internal var isUsingMultipeerConnectivityTransport : Bool {
        return session is MultipeerSessionTransport
    }

    internal var isUsingNetworkFrameworkTransport : Bool {
        if #available(iOS 13.0, macOS 10.15, *) {
            return session is NetworkPeerSessionTransport
        }
        return false
    }

    private static func transportFactory(for backend: PeerConnectionBackend,
        networkSecurity: PeerConnectionNetworkSecurity) -> PeerConnectionTransportFactory {
        switch backend {
        case .multipeerConnectivity:
            return .multipeerConnectivity
        case .networkFramework:
            if #available(iOS 13.0, macOS 10.15, *) {
                return .networkFramework(security: networkSecurity)
            }
            fatalError("PeerConnectivity: Network framework backend requires iOS 13.0 or macOS 10.15")
        }
    }

    internal func handleCertificate(peer: Peer, certificate: [Any]?, handler: @escaping (Bool) -> Void) {
        switch securityConfiguration.certificatePolicy {
        case .acceptAll:
            handler(true)
        case .rejectAll:
            handler(false)
        case .requireCertificate:
            handler(certificate?.isEmpty == false)
        case .custom(let certificateHandler):
            certificateHandler(peer, certificate, handler)
        }

        emit(.receivedCertificate(peer: peer, certificate: certificate, handler: { _ in }))
    }

    internal func handleInvitation(peer: Peer,
                                   context: Data?,
                                   invitationHandler: @escaping (Bool, MultipeerSessionTransport) -> Void) {
        let completeInvitation = { [weak self] (accept: Bool) -> Void in
            guard let strongSelf = self,
                  let session = strongSelf.session as? MultipeerSessionTransport else { return }
            invitationHandler(accept, session)
            if accept && strongSelf.connectionType == .automatic {
                strongSelf.advertiser.stopAdvertising()
            }
        }

        guard connectionType == .automatic else {
            emit(.receivedInvitation(peer: peer,
                                     withContext: context,
                                     invitationHandler: completeInvitation))
            return
        }

        switch invitationPolicy {
        case .manual:
            emit(.receivedInvitation(peer: peer,
                                     withContext: context,
                                     invitationHandler: completeInvitation))
        case .acceptAll:
            emit(.receivedInvitation(peer: peer,
                                     withContext: context,
                                     invitationHandler: { _ in }))
            completeInvitation(true)
        case .rejectAll:
            emit(.receivedInvitation(peer: peer,
                                     withContext: context,
                                     invitationHandler: { _ in }))
            completeInvitation(false)
        case .custom(let invitationPolicy):
            emit(.receivedInvitation(peer: peer,
                                     withContext: context,
                                     invitationHandler: { _ in }))
            completeInvitation(invitationPolicy(peer, context))
        }
    }
}

extension PeerConnectionManager {
    // MARK: Using the PeerConnectionManager
    
    /**
     Start the connection manager with optional completion. Calling this initiates browsing and advertising using the specified connection type.
     
     - parameter completion: Called once session is initialized. Default is `nil`.
     */
    public func start(_ completion: (()->Void)? = nil) {
        startAdvertisingAndBrowsing(completion)
    }

    /**
     Start browsing and advertising with optional completion.

     - parameter completion: Called once session is initialized. Default is `nil`.
     */
    public func startAdvertisingAndBrowsing(_ completion: (()->Void)? = nil) {
        startupMode = .advertisingAndBrowsing
        startCurrentMode(completion)
    }

    /**
     Start browsing without advertising the local peer.

     Use this mode when the local device should discover and invite nearby
     advertisers, but should not itself be discoverable by other peers.

     - parameter completion: Called once session is initialized. Default is `nil`.
     */
    public func startBrowsingOnly(_ completion: (()->Void)? = nil) {
        startupMode = .browsingOnly
        startCurrentMode(completion)
    }

    /**
     Start advertising without browsing for nearby peers.

     Use this mode when the local device should be discoverable and accept
     invitations, but should not itself discover or invite nearby peers.

     - parameter completion: Called once session is initialized. Default is `nil`.
     */
    public func startAdvertisingOnly(_ completion: (()->Void)? = nil) {
        startupMode = .advertisingOnly
        startCurrentMode(completion)
    }
    
    /**
     Use to invite peers that have been found locally to join the current session.

     With `.networkFramework`, `context` and `timeout` are currently ignored and the
     discovered peer endpoint is connected directly when available.
     
     - parameter peer: `Peer` object to invite to current session.
     - parameter withContext: `Data` object associated with the invitation.
     - parameter timeout: Time interval until the invitation expires.
     */
    public func invitePeer(_ peer: Peer, withContext context: Data? = nil, timeout: TimeInterval = 30) {
        browser.invitePeer(peer, withContext: context, timeout: timeout)
    }
    
    /**
     Send data to connected users. If no peer is specified it broadcasts to all users on a current session.
     
     - parameter data: Data to be sent to specified peers.
     - parameter toPeers: Specified `Peer` objects to send data.
     */
    public func sendData(_ data: Data, toPeers peers: [Peer] = []) {
        session.sendData(data, toPeers: peers)
    }
    
    /**
     Send events to connected users. Encoded as Data using the NSKeyedArchiver. If no peer is specified it broadcasts to all users on a current session.

     - parameter eventInfo: Dictionary of Any data which is encoded with the NSKeyedArchiver and passed to the specified peers.
     - parameter toPeers: Specified `Peer` objects to send event.
     */
    @available(*, deprecated, message: "Use sendMessage(_:toPeers:) with PeerMessage types for type-safe messaging")
    public func sendEvent(_ eventInfo: [String:Any], toPeers peers: [Peer] = []) {
        do {
            let eventData = try NSKeyedArchiver.archivedData(withRootObject: eventInfo, requiringSecureCoding: true)
            session.sendData(eventData, toPeers: peers)
        } catch {
            NSLog(error.localizedDescription)
        }
    }

    /**
     Send a type-safe Codable message to connected peers.

     This is the modern alternative to `sendEvent(_:toPeers:)`. Messages are JSON-encoded
     and include type information for routing on the receiving end.

     Example:
     ```swift
     struct ChatMessage: PeerMessage {
         let text: String
         let timestamp: Date
     }

     let message = ChatMessage(text: "Hello!", timestamp: Date())
     pcm.sendMessage(message)
     ```

     - parameter message: The message conforming to `PeerMessage` protocol.
     - parameter toPeers: Specific peers to send to, or empty to broadcast to all connected peers.
     */
    public func sendMessage<T: PeerMessage>(_ message: T, toPeers peers: [Peer] = []) {
        do {
            var envelope: [String: Data] = [:]
            envelope["type"] = T.messageType.data(using: .utf8)
            envelope["payload"] = try JSONEncoder().encode(message)
            let data = try JSONEncoder().encode(envelope)
            session.sendData(data, toPeers: peers)
        } catch {
            NSLog("PeerConnectivity: Failed to encode message: \(error.localizedDescription)")
        }
    }

    /**
     Send a data stream to a connected user. This method throws an error if the stream cannot be established. This method returns the NSOutputStream with which you can send events to the connected users.

     This API is MultipeerConnectivity-only in the current migration. The Network
     framework backend throws a `PeerConnectivity.NetworkPeerSessionTransport`
     unsupported-operation error.
     
     - parameter streamName: The name of the stream to be established between two users.
     - parameter toPeer: The peer with which to start a data stream
     
     - Throws: Propagates errors thrown by Apple's MultipeerConnectivity framework, or a Network backend unsupported-operation error.
     
     - Returns: The OutputStream for sending information to the specified `Peer` object.
     */
    public func sendDataStream(streamName name: String, toPeer peer: Peer) throws -> OutputStream {
        do { return try session.sendDataStream(name, toPeer: peer) }
        catch let error { throw error }
    }
    
    /**
     Send a resource with a specified url for retrieval on a connected device. This method can send a resource to multiple peers and returns an Progress associated with each Peer. This method takes an error completion handler if the resource fails to send.

     This API is MultipeerConnectivity-only in the current migration. The Network
     framework backend returns `nil` progress for each requested peer and calls the
     completion handler with a `PeerConnectivity.NetworkPeerSessionTransport`
     unsupported-operation error.
     
     - parameter resourceURL: The url that the resource will be passed with for retrieval.
     - parameter withName: The name with which the progress is associated with.
     - parameter toPeers: The specified peers for the resource to be sent to.
     - parameter withCompletionHandler: the completion handler called when an error is thrown sending a resource.
     
     - Returns: A dictionary of optional Progress associated with each peer that the resource was sent to.
     */
    public func sendResourceAtURL(_ resourceURL: URL, withName name: String, toPeers peers: [Peer] = [], withCompletionHandler completion: ((Error?) -> Void)? ) -> [Peer:Progress?] {
        
        var progress : [Peer:Progress?] = [:]
        let peers = (peers.isEmpty) ? self.connectedPeers : peers
        for peer in peers {
            progress[peer] = session.sendResourceAtURL(resourceURL, withName: name, toPeer: peer, withCompletionHandler: completion)
        }
        return progress
    }
    
    /**
     Refresh the current session. This call disconnects the user from the current session and then restarts the session with completion maintaing the current sessions configuration.
     
     - parameter completion: Completion handler called after the session has completed refreshing.
     */
    public func refresh(_ completion: (()->Void)? = nil) {
        stop()
        startCurrentMode(completion)
    }
    
    /**
     Stop the current connection manager from listening to delegate callbacks and disconnects from the current session.
     */
    public func stop() {
        advanceTransportEventGeneration()
        emit(.ended)
        
        session.stopSession()
        browser.stopBrowsing()
        advertiser.stopAdvertising()
        advertiserAssisstant.stopAdvertisingAssisstant()
        foundPeers = []
        
        sessionObserver.removeAllObservers()
        browserObserver.removeAllObservers()
        advertiserObserver.removeAllObservers()
        advertiserAssisstantObserver.removeAllObservers()
        sessionObserver.update(.none)
        browserObserver.update(.none)
        advertiserObserver.update(.none)
        advertiserAssisstantObserver.update(.none)
        
        emit(.ready)
    }
    
    /**
     Close session for browsing peers to invite.
     */
    public func closeSession() {
        browser.stopBrowsing()
    }
    
    /**
     Open session for browsing peers to invite.
     */
    public func openSession() {
        browser.startBrowsing()
    }

    private func emit(_ event: PeerConnectionEvent) {
        observer.update(event)
    }

    private func advanceTransportEventGeneration() {
        transportEventGenerationLock.lock()
        transportEventGeneration += 1
        transportEventGenerationLock.unlock()
    }

    private func currentTransportEventGeneration() -> Int {
        transportEventGenerationLock.lock()
        let generation = transportEventGeneration
        transportEventGenerationLock.unlock()
        return generation
    }

    private func isCurrentTransportEventGeneration(_ generation: Int) -> Bool {
        return currentTransportEventGeneration() == generation
    }

    private func startCurrentMode(_ completion: (() -> Void)? = nil) {
        advanceTransportEventGeneration()
        let generation = currentTransportEventGeneration()
        let mode = startupMode

        Task {
            switch mode {
            case .advertisingAndBrowsing:
                await prepareForStart(includeBrowserObservers: true, includeAdvertiserObservers: true, generation: generation)
                await startConfiguredSession(shouldBrowse: true, shouldAdvertise: true, generation: generation, completion)
            case .browsingOnly:
                await prepareForStart(includeBrowserObservers: true, includeAdvertiserObservers: false, generation: generation)
                await startConfiguredSession(shouldBrowse: true, shouldAdvertise: false, generation: generation, completion)
            case .advertisingOnly:
                await prepareForStart(includeBrowserObservers: false, includeAdvertiserObservers: true, generation: generation)
                await startConfiguredSession(shouldBrowse: false, shouldAdvertise: true, generation: generation, completion)
            }
        }
    }

    private func prepareForStart(includeBrowserObservers: Bool, includeAdvertiserObservers: Bool, generation: Int) async {
        if includeBrowserObservers {
            await browserObserver.addObserverAsync { [weak self] event in
                guard self?.isCurrentTransportEventGeneration(generation) == true else { return }

                switch event {
                case .foundPeer(let peer, let discoveryInfo):
                    self?.emit(.foundPeer(peer: peer))
                    self?.emit(.foundPeerWithDiscoveryInfo(peer: peer, discoveryInfo: discoveryInfo))
                case .lostPeer(let peer):
                    self?.emit(.lostPeer(peer: peer))
                case .didNotStartBrowsingForPeers(let error):
                    self?.emit(.error(error))
                default: break
                }
            }
        }

        if includeAdvertiserObservers {
            await advertiserObserver.addObserverAsync { [weak self] event in
                guard self?.isCurrentTransportEventGeneration(generation) == true else { return }

                switch event {
                case .didReceiveInvitationFromPeer(peer: let peer, withContext: let context, invitationHandler: let invite):
                    self?.handleInvitation(peer: peer, context: context, invitationHandler: invite)
                case .didNotStartAdvertisingPeer(let error):
                    self?.emit(.error(error))
                default: break
                }
            }
        }

        await sessionObserver.addObserverAsync { [weak self] event in
            guard self?.isCurrentTransportEventGeneration(generation) == true else { return }

            switch event {
            case .devicesChanged(peer: let peer):
                guard let connectedPeers = self?.connectedPeers else { break }
                self?.emit(.devicesChanged(peer: peer, connectedPeers: connectedPeers))
            case .didReceiveData(peer: let peer, data: let data):
                self?.emit(.receivedData(peer: peer, data: data))

                // Try modern JSON envelope first (from sendMessage)
                if let envelope = try? JSONDecoder().decode([String: Data].self, from: data),
                   let typeData = envelope["type"],
                   let messageType = String(data: typeData, encoding: .utf8),
                   let payload = envelope["payload"] {
                    self?.emit(.receivedMessage(peer: peer, messageType: messageType, data: payload))
                    return
                }

                // Fall back to legacy NSKeyedArchiver format (from sendEvent)
                guard let eventInfo = try? NSKeyedUnarchiver.unarchivedObject(
                    ofClasses: [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSDate.self, NSData.self],
                    from: data
                ) as? [String: Any] else { return }
                self?.emit(.receivedEvent(peer: peer, eventInfo: eventInfo))
            case .didReceiveCertificate(peer: let peer, certificate: let certificate, handler: let handler):
                self?.handleCertificate(peer: peer, certificate: certificate, handler: handler)
            case .didReceiveStream(peer: let peer, stream: let stream, name: let name):
                self?.emit(.receivedStream(peer: peer, stream: stream, name: name))
            case .startedReceivingResource(peer: let peer, name: let name, progress: let progress):
                self?.emit(.startedReceivingResource(peer: peer, name: name, progress: progress))
            case .finishedReceivingResource(peer: let peer, name: let name, url: let url, error: let error):
                self?.emit(.finishedReceivingResource(peer: peer, name: name, url: url, error: error))
            default: break
            }
        }

        if includeBrowserObservers {
            await browserObserver.addObserverAsync { [weak self] event in
                guard self?.isCurrentTransportEventGeneration(generation) == true else { return }

                DispatchQueue.main.async {
                    guard self?.isCurrentTransportEventGeneration(generation) == true else { return }

                    switch event {
                    case .foundPeer(let peer, _):
                        guard let peers = self?.foundPeers , !peers.contains(peer) else { break }
                        self?.foundPeers.append(peer)
                    case .lostPeer(let peer):
                        guard let index = self?.foundPeers.firstIndex(of: peer) else { break }
                        self?.foundPeers.remove(at: index)
                    default: break
                    }
                }
            }
        }

        await sessionObserver.addObserverAsync { [weak self] event in
            guard self?.isCurrentTransportEventGeneration(generation) == true else { return }

            DispatchQueue.main.async {
                guard self?.isCurrentTransportEventGeneration(generation) == true else { return }
                guard self?.backend == .multipeerConnectivity,
                    let peerCount = self?.connectedPeers.count else { return }

                switch event {
                case .devicesChanged(peer: let peer) where peerCount <= 0:
                    switch peer.status {
                    case .notConnected:
                        self?.refresh()
                    default: break
                    }
                default: break
                }
            }
        }
    }

    private func startConfiguredSession(
        shouldBrowse: Bool,
        shouldAdvertise: Bool,
        generation: Int,
        _ completion: (() -> Void)? = nil
    ) async {
        guard isCurrentTransportEventGeneration(generation) else {
            completion?()
            return
        }

        switch connectionType {
        case .automatic:
            if shouldBrowse {
                await prepareAutomaticInviteObserver(generation: generation)
            }
        case .inviteOnly where shouldAdvertise:
            advertiserAssisstant.startAdvertisingAssisstant()
        case .inviteOnly, .custom:
            break
        }

        guard isCurrentTransportEventGeneration(generation) else {
            completion?()
            return
        }

        session.startSession()
        if shouldBrowse {
            browser.startBrowsing()
        }
        if shouldAdvertise {
            advertiser.startAdvertising()
        }

        emit(.started)
        completion?()
    }

    private func prepareAutomaticInviteObserver(generation: Int) async {
        await browserObserver.addObserverAsync { [weak self] event in
            guard self?.isCurrentTransportEventGeneration(generation) == true else { return }

            DispatchQueue.main.async {
                guard self?.isCurrentTransportEventGeneration(generation) == true else { return }

                switch event {
                case .foundPeer(let peer, _):
                    self?.browser.invitePeer(peer)
                default: break
                }
            }
        }
    }
}

extension PeerConnectionManager {
    // MARK: Listening to PeerConnectivity generated events
    
    /**
     Takes a `PeerConnectionEventListener` to respond to events.

     Event delivery is asynchronous. Back-to-back events emitted from synchronous
     call sites are not guaranteed to be delivered in FIFO order by this simple
     actor-backed bridge.
     
     - parameter listener: Takes a `PeerConnectionEventListener`.
     - parameter performListenerInBackground: Default is `false`. Set to `true` to perform the listener asyncronously.
     - parameter withKey: The key with which to associate the listener.
     */
    public func listenOn(_ listener: @escaping PeerConnectionEventListener, performListenerInBackground background: Bool = false, withKey key: String) {
        
        switch background {
        case true:
            responder.addListener(listener, forKey: key)
        case false:
            responder.addListener({ (event) in
                DispatchQueue.main.async(execute: { 
                    listener(event)
                })
            }, forKey: key)
        }
    }
    
    /**
     Takes a key to register the callback and calls the listener when an event is recieved and also passes back the `Peer` that sent it.

     - parameter key: `String` key with which to keep track of the listener for later removal.
     - parameter listener: Callback that returns the event info and the `Peer` whenever an event is received.
     */
    @available(*, deprecated, message: "Use observeMessages(ofType:forKey:listener:) for type-safe messaging")
    public func observeEventListenerForKey(_ key: String, listener: @escaping ([String:Any], Peer)->Void) {
        responder.addListener({ (event) in
            switch event {
            case .receivedEvent(let peer, let eventInfo):
                listener(eventInfo, peer)
            default: break
            }
        }, forKey: key)
    }

    /**
     Listen for specific message types using the modern type-safe API.

     This method automatically decodes incoming messages that match the specified type
     and calls your listener with the decoded message.

     Example:
     ```swift
     struct ChatMessage: PeerMessage {
         let text: String
         let timestamp: Date
     }

     pcm.observeMessages(ofType: ChatMessage.self, forKey: "chat") { message, peer in
         print("\(peer.displayName): \(message.text)")
     }
     ```

     - parameter type: The `PeerMessage` type to listen for.
     - parameter key: The key with which to associate the listener for later removal.
     - parameter listener: Callback that receives the decoded message and the `Peer` that sent it.
     */
    public func observeMessages<T: PeerMessage>(
        ofType type: T.Type,
        forKey key: String,
        listener: @escaping (T, Peer) -> Void
    ) {
        responder.addListener({ event in
            switch event {
            case .receivedMessage(let peer, let messageType, let data)
                where messageType == T.messageType:
                if let message = try? JSONDecoder().decode(T.self, from: data) {
                    DispatchQueue.main.async {
                        listener(message, peer)
                    }
                }
            default: break
            }
        }, forKey: key)
    }

    /**
     Remove a listener associated with a specified key.
     
     - parameter key: The key with which to attempt to find and remove a listener with.
     */
    public func removeListenerForKey(_ key: String) {
        responder.removeListenerForKey(key)
    }

    internal func removeListenerForKeyAsync(_ key: String) async {
        await responder.removeListenerForKeyAsync(key)
    }
    
    /**
     Remove all listeners.
     */
    public func removeAllListeners() {
        responder.removeAllListeners()
    }

    internal func removeAllListenersAsync() async {
        await responder.removeAllListenersAsync()
    }
}
