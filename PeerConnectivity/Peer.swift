//
//  Peer.swift
//  GameController
//
//  Created by Reid Chatham on 12/19/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

/* 
 Enum representing peers by their connection status.
 */
public struct Peer {
    
    /* 
     Peer connection status.
     */
    public enum Status {
        /*
         Represents the current user.
         */
        case CurrentUser
        /*
         Represents a connected user.
         */
        case Connected
        /*
         Represents a connecting user.
         */
        case Connecting
        /*
         Represents a user not connected to the current session. Either someone that is available to be invited to the current session or someone that has lost connection to the current session.
         */
        case NotConnected
    }
    
    /* 
     The peer's display name
     */
    public var displayName : String {
        return peerID.displayName
    }
    
    
    
    internal let peerID : MCPeerID
    
    public let status : Status
    
    internal init(peerID: MCPeerID, status: Status) {
        self.peerID = peerID
        self.status = status
    }
    
    /* 
     Initializer for the local peer. DisplayName Must not be longer than 63 bytes in UTF8 Encoding according to the Apple documentation. ( xcdoc://?url=developer.apple.com/library/ios/documentation/MultipeerConnectivity/Reference/MCPeerID_class/index.html#//apple_ref/swift/cl/c:objc(cs)MCPeerID )
     */
    internal init(displayName: String) {
        peerID = MCPeerID(displayName: displayName)
        status = .CurrentUser
    }
}

extension Peer : Equatable {}
/* 
 Equatable conformance for Peer. 
 */
public func ==(lhs: Peer, rhs: Peer) -> Bool {
    return lhs.peerID == rhs.peerID
}

extension Peer : Hashable {
    /* 
     A hashvalue representing the peer. 
     */
    public var hashValue : Int {
        return peerID.hashValue
    }
}