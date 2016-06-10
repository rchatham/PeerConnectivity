//: Playground - noun: a place where people can play

import UIKit
import PeerConnectivity

// Default joins mpc rooms automatically and uses the users device name as the display name
var pcm = PeerConnectionManager(serviceType: "local")

// Can join chatrooms using .Automatic, .InviteOnly, and .Custom
pcm = PeerConnectionManager(serviceType: "local", connectionType: .Custom, peer: Peer(displayName: "I_AM_KING"))



// Create events as [Strng:AnyObject] Dictionaries
let event: [String: AnyObject] = [
    "EventKey" : NSDate()
]

// Sends to all connected peers
pcm.sendEvent(event)

//Use this to access the connectedPeers [Peer]
let connectedPeers = pcm.connectedPeers

// DO NOT CREATE PEERS THIS WAY. ONLY CREATE THE LOCAL PEER ONCE USING THIS.
// ALWAYS GET PEERS FROM .connectedPeers
let somePeerThatIAmConnectedTo = Peer(displayName: "donotcreatethisway")

// Events can be sent to specific peers
pcm.sendEvent(event, toPeers: [somePeerThatIAmConnectedTo])



let eventListener: EventListener = { (peer: Peer, eventInfo: [String:AnyObject]) in
    print("Received some event \(eventInfo) from \(peer.displayName)")
    
    guard let date = eventInfo["EventKey"] as? NSDate else { return }
    print(date)
}

// Set up listeners
pcm.listenOn(eventReceived: eventListener, withKey: "SomeEvent")

// Start peerconnectivity
pcm.start()

// Add and remove listeners at any time
pcm.removeListenerForKey("SomeEvent")

// String adding multiple listeners together
pcm.listenOn(eventReceived: eventListener, withKey: "SomeEvent")
   .listenOn(devicesChanged: { (peer, connectedPeers) in
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
            invitationContext: [String:String] = NSKeyedUnarchiver.unarchiveObjectWithData(context) as? [String:String],
            isItCool = invitationContext["ThisSession"]
            else { return }
        
        shouldJoin = (isItCool == "IsCool")
        
    }, withKey: "ConnectManually")

// Found peers includes peers that have already joined the session
let peersAvailableForInvite = pcm.foundPeers.filter{ !pcm.connectedPeers.contains($0) }

for peer in peersAvailableForInvite {
    pcm.invitePeer(peer)
}

// Stop the connection manager
// Always stop running connection managers before changing
pcm.stop()
// Restart at any time

pcm.refresh() // Calls .stop() then .start()
// Use after changing information affecting how you want to connect to peers in your current session

pcm.stop()


// TODO: - Add streams




