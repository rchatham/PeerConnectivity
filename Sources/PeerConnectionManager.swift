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
 */
public typealias ServiceType = String

/**
 Struct representing specified keys for configuring a connection manager.
 */
public struct PeerConnectivityKeys {
    static fileprivate let CertificateListener = "CertificateRecievedListener"
}


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
 The `.networkFramework` backend is an opt-in migration path and does not yet provide
 full parity for MultipeerConnectivity browser UI, streams, or resource transfer.
 */
public enum PeerConnectionBackend : Equatable {
    /**
     Use Apple's MultipeerConnectivity framework. This is the default backend.
     */
    case multipeerConnectivity
    /**
     Use Apple's Network framework. This backend is experimental and currently supports
     discovery, connection scaffolding, and reliable data transport only.
     */
    case networkFramework
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
    
    // MARK: Properties
    /**
     The connection type for the connection manager. (ex. `.automatic`, `.inviteOnly`, `.custom`)
     */
    public let connectionType : PeerConnectionType

    /**
     The backend implementation used by this connection manager.

     The default value is `.multipeerConnectivity`. The `.networkFramework` backend is
     opt-in and does not yet provide browser UI, stream, or resource transfer parity.
     */
    public let backend : PeerConnectionBackend
    
    /**
     Access to the local peer representing the user.
     */
    public let peer : Peer
    
    /**
     Returns the peers that are connected on the current session.
     */
    public var connectedPeers : [Peer] {
        return session.connectedPeers
    }

    /**
     The MultipeerConnectivity session used by this connection manager.

     This is exposed for platform-specific helper packages such as `PeerConnectivityUI`.

     - Warning: Only available when `backend == .multipeerConnectivity`. Accessing this
     property with `.networkFramework` is a programmer error.
     */
    public var multipeerSession : MCSession {
        guard let session = session as? MultipeerSessionTransport else {
            fatalError("PeerConnectivity: multipeerSession is only available for MultipeerConnectivity transports")
        }
        return session.multipeerSession
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
            observer.value = .nearbyPeersChanged(foundPeers: foundPeers)
        }
    }
    
    
    // Private
    fileprivate let serviceType : ServiceType
    fileprivate var startupMode : PeerConnectionStartupMode = .advertisingAndBrowsing
    
    fileprivate let observer = MultiObservable<PeerConnectionEvent>(.ready)
    
    fileprivate let sessionObserver = Observable<PeerSessionEvent>(.none)
    fileprivate let browserObserver = Observable<PeerBrowserEvent>(.none)
    fileprivate let advertiserObserver = Observable<PeerAdvertiserEvent>(.none)
    fileprivate let advertiserAssisstantObserver = Observable<PeerAdvertiserAssisstantEvent>(.none)
    
    fileprivate let session : PeerSessionTransport
    fileprivate let browser : PeerBrowserTransport
    fileprivate let advertiser : PeerAdvertiserTransport
    fileprivate let advertiserAssisstant : PeerAdvertiserAssisstantTransport
    
    fileprivate let responder : PeerConnectionResponder
    
    
    // MARK: Initializer
    /**
     Initializer for a connection manager. Requires the requested service type. If the connectionType and displayName are not specified the connection manager defaults to .Automatic and using the localized host name where available, falling back to the process host name. The `PeerConnectivityUI` product provides an iOS convenience initializer that uses the current device name.
     
     - parameter serviceType: The requested service type describing the channel on which peers are able to connect.
     - parameter connectionType: Takes a PeerConnectionType case determining the default behavior of the framework.
     - parameter displayName: The local user's display name to other peers.
     - parameter backend: Backend implementation to use. Defaults to `.multipeerConnectivity`.
     
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
                backend: PeerConnectionBackend = .multipeerConnectivity) {
        self.init(serviceType: serviceType,
            connectionType: connectionType,
            displayName: displayName,
            backend: backend,
            transportFactory: PeerConnectionManager.transportFactory(for: backend),
            shouldRegisterSharedManager: true)
    }

    internal convenience init(serviceType: ServiceType,
        connectionType: PeerConnectionType = .automatic,
        displayName: String,
        transportFactory: PeerConnectionTransportFactory) {
        self.init(serviceType: serviceType,
            connectionType: connectionType,
            displayName: displayName,
            backend: .multipeerConnectivity,
            transportFactory: transportFactory,
            shouldRegisterSharedManager: false)
    }

    fileprivate init(serviceType: ServiceType,
        connectionType: PeerConnectionType,
        displayName: String,
        backend: PeerConnectionBackend,
        transportFactory: PeerConnectionTransportFactory,
        shouldRegisterSharedManager: Bool) {
        self.connectionType = connectionType
        self.backend = backend
        self.serviceType = serviceType
        self.peer = Peer(displayName: displayName)

        session = transportFactory.makeSession(peer, sessionObserver)
        browser = transportFactory.makeBrowser(session, serviceType, browserObserver)
        advertiser = transportFactory.makeAdvertiser(session, serviceType, advertiserObserver)
        advertiserAssisstant = transportFactory.makeAdvertiserAssisstant(session, serviceType, advertiserAssisstantObserver)

        responder = PeerConnectionResponder(observer: observer)

        responder.addListener({ (event) in
            switch event {
            case .receivedCertificate(peer: _, certificate: _, handler: let handler):
                handler(true)
            default: break
            }
        }, forKey: PeerConnectivityKeys.CertificateListener)

        guard shouldRegisterSharedManager else { return }
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

    private static func transportFactory(for backend: PeerConnectionBackend) -> PeerConnectionTransportFactory {
        switch backend {
        case .multipeerConnectivity:
            return .multipeerConnectivity
        case .networkFramework:
            if #available(iOS 13.0, macOS 10.15, *) {
                return .networkFramework
            }
            fatalError("PeerConnectivity: Network framework backend requires iOS 13.0 or macOS 10.15")
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
     Use to invite peers that have been found locally to join a MultipeerConnectivity session.
     
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
     
     - parameter streamName: The name of the stream to be established between two users.
     - parameter toPeer: The peer with which to start a data stream
     
     - Throws: Propagates errors thrown by Apple's MultipeerConnectivity framework.
     
     - Returns: The OutputStream for sending information to the specified `Peer` object.
     */
    public func sendDataStream(streamName name: String, toPeer peer: Peer) throws -> OutputStream {
        do { return try session.sendDataStream(name, toPeer: peer) }
        catch let error { throw error }
    }
    
    /**
     Send a resource with a specified url for retrieval on a connected device. This method can send a resource to multiple peers and returns an Progress associated with each Peer. This method takes an error completion handler if the resource fails to send.
     
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
        observer.value = .ended
        
        session.stopSession()
        browser.stopBrowsing()
        advertiser.stopAdvertising()
        advertiserAssisstant.stopAdvertisingAssisstant()
        foundPeers = []
        
        sessionObserver.removeAllObservers()
        browserObserver.removeAllObservers()
        advertiserObserver.removeAllObservers()
        advertiserAssisstantObserver.removeAllObservers()
        
        sessionObserver.value = .none
        browserObserver.value = .none
        advertiserObserver.value = .none
        advertiserAssisstantObserver.value = .none
        
        observer.value = .ready
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

    private func startCurrentMode(_ completion: (() -> Void)? = nil) {
        switch startupMode {
        case .advertisingAndBrowsing:
            prepareForStart(includeBrowserObservers: true, includeAdvertiserObservers: true)
            startConfiguredSession(shouldBrowse: true, shouldAdvertise: true, completion)
        case .browsingOnly:
            prepareForStart(includeBrowserObservers: true, includeAdvertiserObservers: false)
            startConfiguredSession(shouldBrowse: true, shouldAdvertise: false, completion)
        case .advertisingOnly:
            prepareForStart(includeBrowserObservers: false, includeAdvertiserObservers: true)
            startConfiguredSession(shouldBrowse: false, shouldAdvertise: true, completion)
        }
    }

    private func prepareForStart(includeBrowserObservers: Bool, includeAdvertiserObservers: Bool) {
        if includeBrowserObservers {
            browserObserver.addObserver { [weak self] event in
                switch event {
                case .foundPeer(let peer):
                    self?.observer.value = .foundPeer(peer: peer)
                case .lostPeer(let peer):
                    self?.observer.value = .lostPeer(peer: peer)
                case .didNotStartBrowsingForPeers(let error):
                    self?.observer.value = .error(error)
                default: break
                }
            }
        }

        if includeAdvertiserObservers {
            advertiserObserver.addObserver { [weak self] event in
                switch event {
                case .didReceiveInvitationFromPeer(peer: let peer, withContext: let context, invitationHandler: let invite):
                    let invitationReceiver = {
                        [weak self] (accept: Bool) -> Void in
                        guard let session = self?.session as? MultipeerSessionTransport else { return }
                        invite(accept, session)
                    }
                    self?.observer.value = .receivedInvitation(peer: peer, withContext: context, invitationHandler: invitationReceiver)
                case .didNotStartAdvertisingPeer(let error):
                    self?.observer.value = .error(error)
                default: break
                }
            }
        }

        sessionObserver.addObserver { [weak self] event in
            switch event {
            case .devicesChanged(peer: let peer):
                guard let connectedPeers = self?.connectedPeers else { break }
                self?.observer.value = .devicesChanged(peer: peer, connectedPeers: connectedPeers)
            case .didReceiveData(peer: let peer, data: let data):
                self?.observer.value = .receivedData(peer: peer, data: data)

                // Try modern JSON envelope first (from sendMessage)
                if let envelope = try? JSONDecoder().decode([String: Data].self, from: data),
                   let typeData = envelope["type"],
                   let messageType = String(data: typeData, encoding: .utf8),
                   let payload = envelope["payload"] {
                    self?.observer.value = .receivedMessage(peer: peer, messageType: messageType, data: payload)
                    return
                }

                // Fall back to legacy NSKeyedArchiver format (from sendEvent)
                guard let eventInfo = try? NSKeyedUnarchiver.unarchivedObject(
                    ofClasses: [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSDate.self, NSData.self],
                    from: data
                ) as? [String: Any] else { return }
                self?.observer.value = .receivedEvent(peer: peer, eventInfo: eventInfo)
            case .didReceiveCertificate(peer: let peer, certificate: let certificate, handler: let handler):
                self?.observer.value = .receivedCertificate(peer: peer, certificate: certificate, handler: handler)
            case .didReceiveStream(peer: let peer, stream: let stream, name: let name):
                self?.observer.value = .receivedStream(peer: peer, stream: stream, name: name)
            case .startedReceivingResource(peer: let peer, name: let name, progress: let progress):
                self?.observer.value = .startedReceivingResource(peer: peer, name: name, progress: progress)
            case .finishedReceivingResource(peer: let peer, name: let name, url: let url, error: let error):
                self?.observer.value = .finishedReceivingResource(peer: peer, name: name, url: url, error: error)
            default: break
            }
        }

        if includeBrowserObservers {
            browserObserver.addObserver { [weak self] event in
                DispatchQueue.main.async {
                    switch event {
                    case .foundPeer(let peer):
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

        sessionObserver.addObserver { [weak self] event in
            DispatchQueue.main.async {
                guard let peerCount = self?.connectedPeers.count else { return }

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

    private func startConfiguredSession(shouldBrowse: Bool, shouldAdvertise: Bool, _ completion: (() -> Void)? = nil) {
        switch connectionType {
        case .automatic:
            if shouldBrowse {
                browserObserver.addObserver { [unowned self] event in
                    DispatchQueue.main.async {
                        switch event {
                        case .foundPeer(let peer):
                            self.browser.invitePeer(peer)
                        default: break
                        }
                    }
                }
            }
            if shouldAdvertise {
                advertiserObserver.addObserver { [unowned self] event in
                    DispatchQueue.main.async {
                        switch event {
                        case .didReceiveInvitationFromPeer(peer: _, withContext: _, invitationHandler: let handler):
                            guard let session = self.session as? MultipeerSessionTransport else { return }
                            handler(true, session)
                            self.advertiser.stopAdvertising()
                        default: break
                        }
                    }
                }
            }
        case .inviteOnly where shouldAdvertise:
            advertiserAssisstant.startAdvertisingAssisstant()
        case .inviteOnly, .custom:
            break
        }

        session.startSession()
        if shouldBrowse {
            browser.startBrowsing()
        }
        if shouldAdvertise {
            advertiser.startAdvertising()
        }

        observer.value = .started
        completion?()
    }
}

extension PeerConnectionManager {
    // MARK: Listening to PeerConnectivity generated events
    
    /**
     Takes a `PeerConnectionEventListener` to respond to events.
     
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
    
    /**
     Remove all listeners.
     */
    public func removeAllListeners() {
        responder.removeAllListeners()
    }
}
