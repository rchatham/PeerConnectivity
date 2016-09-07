//
//  PeerConnectionManager.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import UIKit

/**
 The service type describing the channel over which connections are made.
 */
public typealias ServiceType = String

/**
 Struct representing specified keys for configuring a connection manager.
 */
public struct PeerConnectivityKeys {
    static private let CertificateListener = "CertificateRecievedListener"
}

/**
 Enum represeting available connection types. `.Automatic`, `.InviteOnly`, `.Custom`.
 */
public enum PeerConnectionType : Int {
    /**
     Connection type where all available devices attempt to connect automatically.
     */
    case Automatic = 0
    /**
     Connection type providing the browser view controller and advertiser assistant giving the user the ability to handle connections with nearby peers.
     */
    case InviteOnly
    /**
     No default connection implementation is given allowing full control for determining approval of connections using custom algorithms.
     */
    case Custom
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
    public private(set) static var shared : [ServiceType:PeerConnectionManager] = [:]
    
    // MARK: Properties
    /**
     The connection type for the connection manager. (ex. .Automatic, .InviteOnly, .Custom)
     */
    public let connectionType : PeerConnectionType
    
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
     Nearby peers available for connecting.
     */
    public private(set) var foundPeers: [Peer] = []
    
    
    // Private
    private let serviceType : ServiceType
    
    private let observer = MultiObservable<PeerConnectionEvent>(.Ready)
    
    private let sessionObserver = Observable<PeerSessionEvent>(.None)
    private let browserObserver = Observable<PeerBrowserEvent>(.None)
    private let browserViewControllerObserver = Observable<PeerBrowserViewControllerEvent>(.None)
    private let advertiserObserver = Observable<PeerAdvertiserEvent>(.None)
    private let advertiserAssisstantObserver = Observable<PeerAdvertiserAssisstantEvent>(.None)
    
    private let sessionEventProducer : PeerSessionEventProducer
    private let browserEventProducer : PeerBrowserEventProducer
    private let browserViewControllerEventProducer : PeerBrowserViewControllerEventProducer
    private let advertiserEventProducer : PeerAdvertiserEventProducer
    private let advertiserAssisstantEventProducer : PeerAdvertiserAssisstantEventProducer
    
    private let session : PeerSession
    private let browser : PeerBrowser
    private let browserAssisstant : PeerBrowserAssisstant
    private let advertiser : PeerAdvertiser
    private let advertiserAssisstant : PeerAdvertiserAssisstant
    
    private let responder : PeerConnectionResponder
    
    
    // MARK: Initializer
    /**
     Initializer for a connection manager. Requires the requested service type. If the connectionType and displayName are not specified the connection manager defaults to .Automatic and using the local device name.
     
     - parameter serviceType: The requested service type describing the channel on which peers are able to connect.
     - parameter connectionType: Takes a PeerConnectionType case determining the default behavior of the framework.
     - parameter displayName: The local user's display name to other peers.
     
     - Returns A fully initialized `PeerConnectionManager`.
     */
    public init(serviceType: ServiceType,
                connectionType: PeerConnectionType = .Automatic,
                displayName: String = UIDevice.currentDevice().name) {
        
        self.connectionType = connectionType
        self.serviceType = serviceType
        self.peer = Peer(displayName: displayName)
        
        sessionEventProducer = PeerSessionEventProducer(observer: sessionObserver)
        browserEventProducer = PeerBrowserEventProducer(observer: browserObserver)
        browserViewControllerEventProducer = PeerBrowserViewControllerEventProducer(observer: browserViewControllerObserver)
        advertiserEventProducer = PeerAdvertiserEventProducer(observer: advertiserObserver)
        advertiserAssisstantEventProducer = PeerAdvertiserAssisstantEventProducer(observer: advertiserAssisstantObserver)
        
        session = PeerSession(peer: peer, eventProducer: sessionEventProducer)
        browser = PeerBrowser(session: session, serviceType: serviceType, eventProducer: browserEventProducer)
        browserAssisstant = PeerBrowserAssisstant(session: session, serviceType: serviceType, eventProducer: browserViewControllerEventProducer)
        advertiser = PeerAdvertiser(session: session, serviceType: serviceType, eventProducer: advertiserEventProducer)
        advertiserAssisstant = PeerAdvertiserAssisstant(session: session, serviceType: serviceType, eventProducer: advertiserAssisstantEventProducer)
        
        responder = PeerConnectionResponder(observer: observer)
        
        // Currently checking security certificates is not yet supported.
        responder.addListener({ (event) in
            switch event {
            case .ReceivedCertificate(peer: _, certificate: _, handler: let handler):
                print("PeerConnectionManager: listenOn: certificateReceived")
                handler(true)
            default: break
            }
        }, forKey: PeerConnectivityKeys.CertificateListener)
        
        // Prevent mingling signals from the same device
        if let existing = PeerConnectionManager.shared[serviceType] {
            existing.stop()
            PeerConnectionManager.shared[serviceType] = self
        }
    }
    
    deinit {
        stop()
        removeAllListeners()
        PeerConnectionManager.shared.removeValueForKey(serviceType)
    }
}

extension PeerConnectionManager {
    // MARK: Using the PeerConnectionManager
    
    /**
     Start the connection manager with optional completion. Calling this initiates browsing and advertising using the specified connection type.
     
     - parameter completion: Called once session is initialized. Default is `nil`.
     */
    public func start(completion: (Void->Void)? = nil) {
        
        browserObserver.addObserver { [weak self] event in
            switch event {
            case .FoundPeer(let peer):
                self?.observer.value = .FoundPeer(peer: peer)
            case .LostPeer(let peer):
                self?.observer.value = .LostPeer(peer: peer)
            default: break
            }
        }
        
        advertiserObserver.addObserver { [weak self] event in
            switch event {
            case.DidReceiveInvitationFromPeer(peer: let peer, withContext: let context, invitationHandler: let invite):
                let invitationReceiver = {
                    [weak self] (accept: Bool) -> Void in
                    guard let session = self?.session else { return }
                    invite(accept, session)
                }
                self?.observer.value = .ReceivedInvitation(peer: peer, withContext: context, invitationHandler: invitationReceiver)
            default: break
            }
        }
        
        sessionObserver.addObserver { [weak self] event in
            switch event {
            case .DevicesChanged(peer: let peer):
                guard let connectedPeers = self?.connectedPeers else { break }
                self?.observer.value = .DevicesChanged(peer: peer, connectedPeers: connectedPeers)
            case .DidReceiveData(peer: let peer, data: let data):
                self?.observer.value = .ReceivedData(peer: peer, data: data)
                guard let event = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? [String:AnyObject] else { return }
                self?.observer.value = .ReceivedEvent(peer: peer, event: event)
            case .DidReceiveCertificate(peer: let peer, certificate: let certificate, handler: let handler):
                self?.observer.value = .ReceivedCertificate(peer: peer, certificate: certificate, handler: handler)
            case .DidReceiveStream(peer: let peer, stream: let stream, name: let name):
                self?.observer.value = .ReceivedStream(peer: peer, stream: stream, name: name)
            case .StartedReceivingResource(peer: let peer, name: let name, progress: let progress):
                self?.observer.value = .StartedReceivingResource(peer: peer, name: name, progress: progress)
            case .FinishedReceivingResource(peer: let peer, name: let name, url: let url, error: let error):
                self?.observer.value = .FinishedReceivingResource(peer: peer, name: name, url: url, error: error)
            default: break
            }
        }
        
        browserObserver.addObserver { [weak self] event in
            dispatch_async(dispatch_get_main_queue()) {
                switch event {
                case .FoundPeer(let peer):
                    guard let peers = self?.foundPeers where !peers.contains(peer) else { break }
                    self?.foundPeers.append(peer)
                case .LostPeer(let peer):
                    guard let index = self?.foundPeers.indexOf(peer) else { break }
                    self?.foundPeers.removeAtIndex(index)
                default: break
                }
                print(self?.foundPeers)
            }
        }
        
        sessionObserver.addObserver { [weak self] event in
            dispatch_async(dispatch_get_main_queue()) {
                guard let peerCount = self?.connectedPeers.count else { return }
                
                switch event {
                case .DevicesChanged(peer: let peer) where peerCount <= 0 :
                    switch peer.status {
                    case .NotConnected:
                        print("Lost Connection")
                        self?.refresh()
                    default: break
                    }
                default: break
                }
            }
        }
        
        switch connectionType {
        case .Automatic:
            browserObserver.addObserver { [unowned self] event in
                dispatch_async(dispatch_get_main_queue()) {
                    switch event {
                    case .FoundPeer(let peer):
                        print("Invite Peer: \(peer.displayName) to session")
                        self.browser.invitePeer(peer)
                    default: break
                    }
                }
            }
            advertiserObserver.addObserver { [unowned self] event in
                dispatch_async(dispatch_get_main_queue()) {
                    switch event {
                    case .DidReceiveInvitationFromPeer(peer: _, withContext: _, invitationHandler: let handler):
                        print("Responding to invitation")
                        handler(true, self.session)
                        self.advertiser.stopAdvertising()
                    default: break
                    }
                }
            }
        case .InviteOnly:
            advertiserAssisstant.startAdvertisingAssisstant()
        case .Custom: break
        }
        
        session.startSession()
        browser.startBrowsing()
        advertiser.startAdvertising()
        
        observer.value = .Started
        completion?()
    }
    
    /**
     Returns a browser view controller if the connectionType was set to `.InviteOnly` or returns `nil` if not.
     
     - parameter callback: Events sent back with cases `.DidFinish` and `.DidCancel`.
     
     - Returns: A browser view controller for inviting available peers nearby if connection type is `.InviteOnly` or `nil` otherwise.
     */
    public func browserViewController(callback: PeerBrowserViewControllerEvent->Void) -> UIViewController? {
        browserViewControllerObserver.addObserver { callback($0) }
        switch connectionType {
        case .InviteOnly: return browserAssisstant.peerBrowserViewController()
        default: return nil
        }
    }
    
    /**
     Use to invite peers that have been found locally to join a MultipeerConnectivity session.
     
     - parameter peer: `Peer` object to invite to current session.
     - parameter withContext: `NSData` object associated with the invitation.
     - parameter timeout: Time interval until the invitation expires.
     */
    public func invitePeer(peer: Peer, withContext context: NSData? = nil, timeout: NSTimeInterval = 30) {
        browser.invitePeer(peer, withContext: context, timeout: timeout)
    }
    
    /**
     Send data to connected users. If no peer is specified it broadcasts to all users on a current session.
     
     - parameter data: Data to be sent to specified peers.
     - parameter toPeers: Specified `Peer` objects to send data.
     */
    public func sendData(data: NSData, toPeers peers: [Peer] = []) {
        session.sendData(data, toPeers: peers)
    }
    
    /**
     Send events to connected users. Encoded as NSData using the NSKeyedArchiver. If no peer is specified it broadcasts to all users on a current session.
     
     - parameter eventInfo: Dictionary of AnyObject data which is encoded with the NSKeyedArchiver and passed to the specified peers.
     - parameter toPeers: Specified `Peer` objects to send event.
     */
    public func sendEvent(eventInfo: [String:AnyObject], toPeers peers: [Peer] = []) {
        let eventData = NSKeyedArchiver.archivedDataWithRootObject(eventInfo)
        session.sendData(eventData, toPeers: peers)
    }
    
    /**
     Send a data stream to a connected user. This method throws an error if the stream cannot be established. This method returns the NSOutputStream with which you can send events to the connected users.
     
     - parameter streamName: The name of the stream to be established between two users.
     - parameter toPeer: The peer with which to start a data stream
     
     - Throws: Propagates errors thrown by Apple's MultipeerConnectivity framework.
     */
    public func sendDataStream(streamName name: String, toPeer peer: Peer) throws -> NSOutputStream {
        do { return try session.sendDataStream(name, toPeer: peer) }
        catch let error { throw error }
    }
    
    /**
     Send a resource with a specified url for retrieval on a connected device. This method can send a resource to multiple peers and returns an NSProgress associated with each Peer. This method takes an error completion handler if the resource fails to send.
     
     - parameter resourceURL: The url that the resource will be passed with for retrieval.
     - parameter withName: The name with which the progress is associated with.
     - parameter toPeers: The specified peers for the resource to be sent to.
     - parameter withCompletionHandler: the completion handler called when an error is thrown sending a resource.
     
     - Returns: A dictionary of optional NSProgress associated with each peer that the resource was sent to.
     */
    public func sendResourceAtURL(resourceURL: NSURL, withName name: String, toPeers peers: [Peer] = [], withCompletionHandler completion: (NSError? -> Void)? ) -> [Peer:NSProgress?] {
        
        var progress : [Peer:NSProgress?] = [:]
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
    public func refresh(completion: (Void->Void)? = nil) {
        stop()
        start(completion)
    }
    
    /**
     Stop the current connection manager from listening to delegate callbacks and disconnects from the current session.
     */
    public func stop() {
        observer.value = .Ended
        
        session.stopSession()
        browser.stopBrowsing()
        advertiser.stopAdvertising()
        advertiserAssisstant.stopAdvertisingAssisstant()
        foundPeers = []
        
        sessionObserver.observers = []
        browserObserver.observers = []
        advertiserObserver.observers = []
        advertiserAssisstantObserver.observers = []
        browserViewControllerObserver.observers = []
        
        sessionObserver.value = .None
        browserObserver.value = .None
        advertiserObserver.value = .None
        advertiserAssisstantObserver.value = .None
        browserViewControllerObserver.value = .None
        
        observer.value = .Ready
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
}

extension PeerConnectionManager {
    // MARK: Listening to PeerConnectivity generated events
    
    /**
     Takes a `PeerConnectionEventListener` to respond to events.
     
     - parameter listener: Takes a `PeerConnectionEventListener`.
     - parameter withKey: The key with which to associate the listener.
     
     - warning: All listeners are performed asyncronously. You must be sure to dispatch_async to the main queue if you intend to use these listeners from the main thread.
     */
    public func listenOn(listener: PeerConnectionEventListener, withKey key: String) {
        responder.addListener(listener, forKey: key)
    }
    
    /**
     Remove a listener associated with a specified key.
     
     - parameter key: The key with which to attempt to find and remove a listener with.
     */
    public func removeListenerForKey(key: String) {
        responder.removeListenerForKey(key)
    }
    
    /**
     Remove all listeners.
     */
    public func removeAllListeners() {
        responder.removeAllListeners()
    }
}
