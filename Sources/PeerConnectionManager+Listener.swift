//
//  PeerConnectionManager+Listener.swift
//  PeerConnectivity
//
//  Created by Julien Di Marco on 25/10/2018.
//  Copyright © 2018 Reid Chatham. All rights reserved.
//

import Foundation

// MARK: - Manager listener management -

public extension PeerConnectionManager {

    /// Takes a `PeerConnectionEventListener` to respond to events.
    ///
    /// - parameter listener: Takes a `PeerConnectionEventListener`.
    /// - parameter performListenerInBackground: Default is `false`. Set to `true` to perform the listener asyncronously.
    /// - parameter withKey: The key with which to associate the listener.

    public func listenOn(_ listener: @escaping PeerConnectionEventListener,
                         performListenerInBackground background: Bool = false, withKey key: String) {

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

    /// Takes a key to register the callback and calls the listener when an event is recieved and also passes back the `Peer` that sent it.
    ///
    /// - parameter key: `String` key with which to keep track of the listener for later removal.
    /// - parameter listener: Callback that returns the event info and the `Peer` whenever an event is received.

    public func observeEventListenerForKey(_ key: String, listener: @escaping ([String: Any], PeerSession, Peer) -> Void) {
        responder.addListener({ (event) in
            switch event {
            case .receivedEvent(let session, let peer, let eventInfo):
                listener(eventInfo, session, peer)
            default: break
            }
        }, forKey: key)
    }


    /// Remove a listener associated with a specified key.
    ///
    /// - parameter key: The key with which to attempt to find and remove a listener with.

    public func removeListenerForKey(_ key: String) {
        responder.removeListenerForKey(key)
    }

    /// Remove all listeners.
    public func removeAllListeners() {
        responder.removeAllListeners()
    }

}
