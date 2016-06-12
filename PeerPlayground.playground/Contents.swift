//: Playground - noun: a place where people can play

import UIKit
import PeerConnectivity


/*
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

// Can join chatrooms using .Automatic, .InviteOnly, and .Custom
// The manager can be initialized with a contructed peer representing the local user
// with a custom displayName
pcm = PeerConnectionManager(serviceType: "local", connectionType: .Custom, peer: Peer(displayName: "I_AM_KING"))

// Start again at any time
pcm.start() {
    // Do something when finished starting the session
}



// MARK: - Inviting peers/ Handling invitations

// Add multiple listeners with one key
pcm.listenOn(foundPeer: { (peer) in
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
    
}, lostPeer: { (peer) in
    print("Lost peer \(peer.displayName)")
    
}, receivedInvitation: { (peer, withContext, invitationHandler) in
    print("\(peer.displayName) invited you to join their session")
    
    var shouldJoin = false
    
    defer {
        invitationHandler(shouldJoin)
    }
    
    guard let context = withContext,
        invitationContext = NSKeyedUnarchiver.unarchiveObjectWithData(context) as? [String:String],
        isItCool = invitationContext["ThisSession"]
        else { return }
    
    shouldJoin = (isItCool == "IsCool")
    
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

// DO NOT CREATE PEERS THIS WAY. ONLY CREATE THE LOCAL PEER ONCE USING THIS.
// ALWAYS GET PEERS FROM .connectedPeers
let somePeerThatIAmConnectedTo = Peer(displayName: "donotcreatethisway")

switch somePeerThatIAmConnectedTo {
case .CurrentUser:
    print("Was created by current user")
default:
    print("Something else happened")
}

// Events can be sent to specific peers
pcm.sendEvent(event, toPeers: [somePeerThatIAmConnectedTo])

let stream = try? pcm.sendDataStream(streamName: "some-stream", toPeer: somePeerThatIAmConnectedTo)

if let stream = stream {
    // Do something with stream
} else {
    // Error: Stream failed
    // Can use do {} catch let error {} to handle error
}

let progress: [Peer:NSProgress?] = pcm.sendResourceAtURL(NSURL(string: "someurl")!, withName: "resource-name", toPeers: [somePeerThatIAmConnectedTo]) { (error: NSError?) in
    // Handle some error
    print("Error: \(error)")
}



// MARK: - Handling incoming events/notifications

// It is generally a good idea to configure your peer session before calling .start()

// Create an event listener
let eventListener: EventListener = { (peer: Peer, eventInfo: [String:AnyObject]) in
    print("Received some event \(eventInfo) from \(peer.displayName)")
    
    guard let date = eventInfo["EventKey"] as? NSDate else { return }
    print(date)
}

// Set up listeners
pcm.listenOn(eventReceived: eventListener, withKey: "SomeEvent")

// Add and remove listeners at any time
pcm.removeListenerForKey("SomeEvent")

// String adding multiple listeners together
pcm.listenOn(eventReceived: eventListener, withKey: "SomeEvent")
   .listenOn(devicesChanged: { (peer, connectedPeers) in
    
    // Get informed about changes in the peers connected to the current session
    switch peer {
    case .Connected :
        print("\(peer.displayName) connected to session")
    case .Connecting :
        print("\(peer.displayName) is attempting to connect")
    case .NotConnected :
        print("\(peer.displayName) disconnected or was unable to connect")
    default : break
    }
}, withKey: "ConnectedDevicesChanged")

// Optionally respond to events asynchronously. Default is false.
pcm.listenOn(eventReceived: eventListener,
             performListenerInBackground: true,
             withKey: "SomeEvent")




// You should always stop the connection manager when you are done with it.
pcm.stop()


// TODO: - Add streams
// TODO: - Test sending resources at URL
// TODO: - Extend service with NSNetService and Bonjour C API for manually
//      configuring the PeerSession.
// TODO: - Add Testing

