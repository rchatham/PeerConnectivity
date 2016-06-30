//
//  PeerConnectionListener.swift
//  GameController
//
//  Created by Reid Chatham on 12/25/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

internal enum PeerConnectionEvent {
    case Ready
    case Started
    case DevicesChanged(peer: Peer, connectedPeers: [Peer])
    case ReceivedData(peer: Peer, data: NSData)
    case ReceivedStream(peer: Peer, stream: NSStream, name: String)
    case StartedReceivingResource(peer: Peer, name: String, progress: NSProgress)
    case FinishedReceivingResource(peer: Peer, name: String, url: NSURL, error: NSError?)
    case ReceivedCertificate(peer: Peer, certificate: [AnyObject]?, handler: (Bool)->Void)
    case Error(PeerConnectionError)
    case Ended
    case FoundPeer(peer: Peer)
    case LostPeer(peer: Peer)
    case ReceivedInvitation(peer: Peer, withContext: NSData?, invitationHandler: (Bool, PeerSession)->Void)
}

public enum PeerConnectionError : ErrorType {
    case Error(NSError)
    case DidNotStartAdvertisingPeer(NSError)
    case DidNotStartBrowsingForPeers(NSError)
}

public typealias ReadyListener = Void->Void
public typealias StartListener = Void->Void
public typealias SessionEndedListener = Void->Void

public typealias DevicesChangedListener = (peer: Peer, connectedPeers: [Peer])->Void
public typealias EventListener = (peer: Peer, eventInfo: [String:AnyObject])->Void
public typealias DataListener = (peer: Peer, data: NSData)->Void
public typealias StreamListener = (peer: Peer, stream: NSStream, name: String)->Void
public typealias StartedReceivingResourceListener = (peer: Peer, name: String, progress: NSProgress)->Void
public typealias FinishedReceivingResourceListener = (peer: Peer, name: String, url: NSURL, error: NSError?)->Void
public typealias CertificateReceivedListener = (peer: Peer, certificate: [AnyObject]?, handler: (Bool) -> Void)->Void
public typealias ErrorListener = (error: PeerConnectionError)->Void

public typealias FoundPeerListener = (peer: Peer)->Void
public typealias LostPeerListener = (peer: Peer)->Void
internal typealias InternalInvitationListener = (peer: Peer, withContext: NSData?, invitationHandler: (Bool, PeerSession) -> Void)->Void
public typealias ReceivedInvitationListener = (peer: Peer, withContext: NSData?, invitationHandler: (Bool) -> Void)->Void

// TODO: Should this be a class or a struct?
internal //struct
class PeerConnectionListener {
    
    private let peerEventObserver : MultiObservable<PeerConnectionEvent>
    
    internal typealias Listener = PeerConnectionEvent->Void
    internal private(set) var listeners : [String:Listener] = [:]
    
    internal init(observer: MultiObservable<PeerConnectionEvent>) {
        peerEventObserver = observer
    }
    
    internal //mutating
    func addListener(listener: Listener, forKey key: String) -> PeerConnectionListener {
        listeners[key] = listener
        peerEventObserver.addObserver(listener, key: key)
        return self
    }
    
    internal //mutating 
    func addListeners(listeners: [String:Listener]) -> PeerConnectionListener {
        listeners.forEach { addListener($0.1, forKey: $0.0) }
        return self
    }
    
    internal //mutating
    func removeAllListeners() {
        listeners = [:]
        peerEventObserver.observers = [:]
    }
    
    internal //mutating
    func removeListenerForKey(key: String) {
        listeners.removeValueForKey(key)
        peerEventObserver.observers.removeValueForKey(key)
    }
    
    internal //mutating
    func listenOn(ready ready: ReadyListener = { _ in },
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
                        receivedInvitation: InternalInvitationListener = { _ in },
                        performListenerInBackground: Bool,
                        withKey key: String) -> PeerConnectionListener {
        
        func switchOnEvent(event: PeerConnectionEvent) {
            switch event {
            case .Ready: ready()
            case .Started: started()
            case .DevicesChanged(peer: let peer, connectedPeers: let peers):
                devicesChanged(peer: peer, connectedPeers: peers)
            case .ReceivedData(peer: let peer, data: let data):
                dataReceived(peer: peer, data: data)
                guard let eventInfo = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? [String:AnyObject] else { return }
                eventReceived(peer: peer, eventInfo: eventInfo)
            case .ReceivedStream(peer: let peer, stream: let stream, name: let name):
                streamReceived(peer: peer, stream: stream, name: name)
            case .StartedReceivingResource(peer: let peer, name: let name, progress: let progress):
                receivingResourceStarted(peer: peer, name: name, progress: progress)
            case .FinishedReceivingResource(peer: let peer, name: let name, url: let url, error: let error):
                receivingResourceFinished(peer: peer, name: name, url: url, error: error)
            case .ReceivedCertificate(peer: let peer, certificate: let certificate, handler: let handler):
                certificateReceived(peer: peer, certificate: certificate, handler: handler)
            case .Ended: ended()
            case .Error(let e): error(error: e)
            case .FoundPeer(peer: let peer): foundPeer(peer: peer)
            case .LostPeer(peer: let peer): lostPeer(peer: peer)
            case .ReceivedInvitation(peer: let peer, withContext: let context, invitationHandler: let invitationHandler):
                receivedInvitation(peer: peer, withContext: context, invitationHandler: invitationHandler)
//            default: break
            }
        }
        
        addListener({ event in
            
            switch performListenerInBackground {
            case true:
                switchOnEvent(event)
            case false:
                dispatch_async(dispatch_get_main_queue()) {
                    switchOnEvent(event)
                }
            }
        }, forKey: key)
        
        return self
    }
}