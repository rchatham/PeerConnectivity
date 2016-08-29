//: Playground - noun: a place where people can play

import UIKit
import PeerConnectivity


/*:
 Welcome to the PeerPlayground!
 
 This playground shows the general workflow of using the PeerConnectivity framework.
 
 The basics:
    1) Creating a PeerConnectionManager
    2) Handling invitations
    3) Sending information
    4) Handling incoming information
*/



// MARK: Creating/Stopping/Starting the manager

// Default joins mpc rooms automatically and uses the users device name as the display name
var pcm = PeerConnectionManager(serviceType: "local")

// Start peerconnectivity
pcm.start()

// Stop the connection manager
// Always stop running connection managers before changing
pcm.stop()

// Can join chatrooms using PeerConnectionType.Automatic, .InviteOnly, and .Custom
//  - .Automatic : automatically searches and joins other devices with the same service type
//  - .InviteOnly : provides a browserViewController and invite alert controllers
//  - .Custom : no default behavior is implemented

// The manager can be initialized with a contructed peer representing the local user
// with a custom displayName

pcm = PeerConnectionManager(serviceType: "local", connectionType: .Custom, displayName: "I_AM_KING")

// Start again at any time
pcm.start() {
    // Do something when finished starting the session
}



// MARK: - Inviting peers/ Handling invitations

pcm.listenOn({ (event: PeerConnectionEvent) in
    
    switch event {
    case .FoundPeer(let peer):
        print("Found peer \(peer.displayName)")
    
        // This is already handled if you initialize the PeerConnectionManager
        // with PeerConnectionType.Automatic.
    
        // Invite peer to your session easily
        pcm.invitePeer(peer)
    
        // Invite peers with context data
        let someInfoAboutSession = [
            "ThisSession" : "IsCool"
        ]
        let sessionContextData = NSKeyedArchiver.archivedDataWithRootObject(someInfoAboutSession)
        pcm.invitePeer(peer, withContext: sessionContextData, timeout: 10)
        
    case .LostPeer(let peer):
        print("Lost peer \(peer.displayName)")
        
    case .ReceivedInvitation(let peer, let context, let invitationHandler):
        print("\(peer.displayName) invited you to join their session")
        
        var shouldJoin = false
        
        defer {
            invitationHandler(shouldJoin)
        }
        
        guard let context = context,
            invitationContext = NSKeyedUnarchiver.unarchiveObjectWithData(context) as? [String:String],
            isItCool = invitationContext["ThisSession"]
            else { return }
        
        shouldJoin = (isItCool == "IsCool")
        
    default: break
    }
}, withKey: "ConnectAutomaticallyIfItsCool")

// Refresh an active session. This will cause you to lose connection to your current session.
// Use after changing information affecting how you want to connect to peers.
// Calls .stop() then .start()
pcm.refresh() {
    // Do something after the session restarts
}

// Found peers includes peers that have already joined the session
let peersAvailableForInvite = pcm.foundPeers.filter{ !pcm.connectedPeers.contains($0) }

// Invite them manually at any time
for peer in peersAvailableForInvite {
    pcm.invitePeer(peer)
}



// MARK: - Sending Events/Information

// Create events as [String:AnyObject] Dictionaries
let event: [String: AnyObject] = [
    "EventKey" : NSDate()
]

// Sends to all connected peers
pcm.sendEvent(event)

// Use this to access the connectedPeers
let connectedPeers: [Peer] = pcm.connectedPeers

if let somePeerThatIAmConnectedTo = connectedPeers.first {
    
    switch somePeerThatIAmConnectedTo.status {
    case .CurrentUser:
        print("Was created by current user")
    default:
        print("Something else happened")
    }
    
    // Events can be sent to specific peers
    pcm.sendEvent(event, toPeers: [somePeerThatIAmConnectedTo])
    
    do {
        let stream = try pcm.sendDataStream(streamName: "some-stream", toPeer: somePeerThatIAmConnectedTo)
        // Do something with stream
    } catch let error {
        print("Error: \(error)")
    }
    
    
    let progress: [Peer:NSProgress?] = pcm.sendResourceAtURL(NSURL(string: "someurl")!, withName: "resource-name", toPeers: [somePeerThatIAmConnectedTo]) { (error: NSError?) in
        // Handle potential error
        print("Error: \(error)")
    }
}



// MARK: - Handling incoming events/notifications

// It is generally a good idea to configure your peer session before calling .start()

// Create an event listener
let eventListener: PeerConnectionEventListener = { event in
    
    switch event {
    case .ReceivedEvent(let peer, let eventInfo):
        print("Received some event \(eventInfo) from \(peer.displayName)")
        guard let date = eventInfo["EventKey"] as? NSDate else { return }
        print(date)
        
    case .ReceivedData(let peer, let data):
        let eventInfo = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? [String:AnyObject]
        print("Received some event \(eventInfo) from \(peer.displayName)")
        guard let date = eventInfo?["EventKey"] as? NSDate else { return }
        print(date)
        
    default: break
    }
}

// Set up listeners
pcm.listenOn(eventListener, withKey: "SomeEvent")

// Add and remove listeners at any time
pcm.removeListenerForKey("SomeEvent")
pcm.listenOn(eventListener, withKey: "SomeEvent")

pcm.listenOn({ (event) in
    
    switch event {
    case .DevicesChanged(let peer, let connectedPeers):
        
        // Get informed about changes in the peers connected to the current session
        switch peer.status {
        case .Connected :
            print("\(peer.displayName) connected to session")
        case .Connecting :
            print("\(peer.displayName) is attempting to connect")
        case .NotConnected :
            print("\(peer.displayName) disconnected or was unable to connect")
        default : break
        }
    default : break
    }
    
}, withKey: "ConnectedDevicesChanged")

// Listen to streams
pcm.listenOn({ event in
    
    switch event {
    case .ReceivedStream(let peer, let stream, let name):
        print("Recieved stream with name: \(name) from peer: \(peer.displayName)")
        // Do something with input stream
        
    default: break
    }
    
}, withKey: "StreamListener")

// Receiving resources
pcm.listenOn({ event in
    
    switch event {
    case .StartedReceivingResource(let peer, let name, let progress):
        // Started receivng resource from peer
        print("Receiving resource with name: \(name) from peer: \(peer.displayName) with progress: \(progress)")
        
    case .FinishedReceivingResource(let peer, let name, let url, let error):
        // Finished receiving resource from peer
        print("Finished receiving resource with name: \(name) from peer: \(peer.displayName) at url: \(url.path) with error: \(error)")
        
    default: break
    }
    
}, withKey: "ResourceListener")



// You should always stop the connection manager when you are done with it.
// Starting a new manager without properly stopping other managers on the same device can
// result in undefined behavior.
pcm.stop()


// TODO: - Extend service with NSNetService and Bonjour C API for manually
//      configuring the PeerSession.
// TODO: - Add Testing

