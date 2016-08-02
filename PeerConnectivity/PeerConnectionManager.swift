//
//  PeerConnectionViewModel2.swift
//  GameController
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import UIKit

public typealias ServiceType = String

/* 
 Struct representing specified keys for configuring a connection manager. Currently only supports
 the CertificateListener for deciding if a users 
 */
public struct PeerConnectivityKeys {
    static let CertificateListener = "CertificateRecievedListener"
}

/* 
 Enum represeting available connection types. .Automatic, .InviteOnly, .Custom
 */
public enum PeerConnectionType : Int {
    case Automatic = 0
    case InviteOnly, Custom
}

//public func ==(lhs: PeerConnectionType, rhs: PeerConnectionType) -> Bool {
//    return lhs.hashValue == rhs.hashValue
//}


/*
 Functional wrapper for Apple's MultipeerConnectivity framework.
 */
public class PeerConnectionManager {
    
    /* 
     Access to shared connection managers by their service type
     */
    public private(set) static var shared : [ServiceType:PeerConnectionManager] = [:]
    
    /* 
     The connection type for the connection manager. (ex. .Automatic, .InviteOnly, .Custom)
     */
    public let connectionType : PeerConnectionType
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
    
    /* 
     Access to the local peer representing the user
     */
    public let peer : Peer
    private let session : PeerSession
    private let browser : PeerBrowser
    private let browserAssisstant : PeerBrowserAssisstant
    private let advertiser : PeerAdvertiser
    private let advertiserAssisstant : PeerAdvertiserAssisstant
    
    private let listener : PeerConnectionListener
    
    /* 
     Returns the peers that are connected on the current session
     */
    public var connectedPeers : [Peer] {
        return session.connectedPeers
    }
    
    /* 
     Returns the peers that can be reached locally registered on the current service type
     */
    public private(set) var foundPeers: [Peer] = []
    
    
    /*
     Initializer for a connection manager. Requires the requested service type. If
     the connectionType and displayName are not specified the connection manager defaults
     to .Automatic and using the local device name.
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
        
        listener = PeerConnectionListener(observer: observer)
        
        listener.listenOn(certificateReceived: { (peer, certificate, handler) -> Void in
            print("PeerConnectionManager: listenOn: certificateReceived")
            handler(true)
            }, performListenerInBackground: true, withKey: PeerConnectivityKeys.CertificateListener)
        
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
    // MARK: Start/Stop
    
    /*
     Start the connection manager with optional completion. Calling this initiates browsing and
     advertising using the specified connection type.
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
            case.DidReceiveInvitationFromPeer(peer: let peer, withContext: let context, invitationHandler: let invitationHandler):
                self?.observer.value = .ReceivedInvitation(peer: peer, withContext: context, invitationHandler: invitationHandler)
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
    
    /*
     Returns a browser view controller if the connectionType was set to .InviteOnly or returns nil if not.
     */
    public func browserViewController(callback: PeerBrowserViewControllerEvent->Void) -> UIViewController? {
        browserViewControllerObserver.addObserver { callback($0) }
        switch connectionType {
        case .InviteOnly: return browserAssisstant.peerBrowserViewController()
        default: return nil
        }
    }
    
    /* 
     Use to invite peers that have been found locally to join a MultipeerConnectivity session.
     */
    public func invitePeer(peer: Peer, withContext context: NSData? = nil, timeout: NSTimeInterval = 30) {
        browser.invitePeer(peer, withContext: context, timeout: timeout)
    }
    
    /* 
     Send data to connected users. Not specifying a peer to send to broadcasts to all users on a current session.
     */
    public func sendData(data: NSData, toPeers peers: [Peer] = []) {
        session.sendData(data, toPeers: peers)
    }
    
    /* 
     Send events to connected users. Encoded as NSData using the NSKeyedArchiver.
     */
    public func sendEvent(eventInfo: [String:AnyObject], toPeers peers: [Peer] = []) {
        let eventData = NSKeyedArchiver.archivedDataWithRootObject(eventInfo)
        session.sendData(eventData, toPeers: peers)
    }
    
    /* 
     Send a data stream to a connected user. This method throws an error if the stream cannot be established.
     This method returns the NSOutputStream with which you can send events to the connected users.
     */
    public func sendDataStream(streamName name: String, toPeer peer: Peer) throws -> NSOutputStream {
        do { return try session.sendDataStream(name, toPeer: peer) }
        catch let error { throw error }
    }
    
    // TODO: Sending resources is untested
    /* 
     Send a resource with a specified url for retrieval on a connected device. This method can send a resource to 
     multiple peers and returns an NSProgress associated with each Peer. This method takes an error completion
     handler if the resource fails to send.
     */
    public func sendResourceAtURL(resourceURL: NSURL, withName name: String, toPeers peers: [Peer] = [], withCompletionHandler completion: (NSError? -> Void)? ) -> [Peer:NSProgress?] {
        
        var progress : [Peer:NSProgress?] = [:]
        let peers = (peers.isEmpty) ? self.connectedPeers : peers
        for peer in peers {
            progress[peer] = session.sendResourceAtURL(resourceURL, withName: name, toPeer: peer, withCompletionHandler: completion)
        }
        return progress
    }
    
    /* 
     Refresh the current session. This call disconnects the user from the current session and then restarts the
     session with completion maintaing the current sessions configuration.
     */
    public func refresh(completion: (Void->Void)? = nil) {
        stop()
        start(completion)
    }
    
    /* 
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
}

extension PeerConnectionManager {
    // MARK: Add listener
    
    /* 
     Listen for peer connection events by passing in event callbacks. Listening configurations are associated
     with specified keys allowing you to easily remove or overwrite a configuration at any time.
     */
    public func listenOn(ready ready: ReadyListener = { _ in },
                               started: StartListener = { _ in },
                               ended: SessionEndedListener = { _ in },
                               devicesChanged: DevicesChangedListener = { _ in },
                               eventReceived: EventListener = { _ in },
                               dataReceived: DataListener = { _ in },
                               streamReceived: StreamListener = { _ in },
                               receivingResourceStarted: StartedReceivingResourceListener = { _ in },
                               receivingResourceFinished: FinishedReceivingResourceListener = { _ in },
                               certificateReceived: CertificateReceivedListener = { _ in },
                               error: ErrorListener = { _ in },
                               foundPeer: FoundPeerListener = { _ in },
                               lostPeer: LostPeerListener = { _ in },
                               receivedInvitation: ReceivedInvitationListener = { _ in },
                               performListenerInBackground: Bool = false,
                               withKey key: String) -> PeerConnectionManager {
        
        let invitationReceiver = {
            [weak self] (peer: Peer, withContext: NSData?, invitationHandler: (Bool, PeerSession) -> Void) in
            
            guard let session = self?.session else { return }
            receivedInvitation(peer: peer, withContext: withContext, invitationHandler: { joinResponse in
                if joinResponse { print("PeerConnectionManager: Join peer session") }
                invitationHandler(joinResponse, session)
            })
        }
        
        listener.listenOn(
            ready: ready,
            started: started,
            ended: ended,
            devicesChanged: devicesChanged,
            eventReceived: eventReceived,
            dataReceived: dataReceived,
            streamReceived: streamReceived,
            receivingResourceStarted: receivingResourceStarted,
            receivingResourceFinished: receivingResourceFinished,
            certificateReceived: certificateReceived,
            error: error,
            foundPeer: foundPeer,
            lostPeer: lostPeer,
            receivedInvitation: invitationReceiver,
            performListenerInBackground: performListenerInBackground,
            withKey: key)
        
        return self
    }
    
    /* 
     Remove a listener associated with a specified key.
     */
    public func removeListenerForKey(key: String) {
        listener.removeListenerForKey(key)
    }
    
    /* 
     Remove all listeners.
     */
    public func removeAllListeners() {
        listener.removeAllListeners()
    }
}
