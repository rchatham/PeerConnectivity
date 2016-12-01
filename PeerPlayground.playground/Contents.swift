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

pcm = PeerConnectionManager(serviceType: "local", connectionType: .custom, displayName: "I_AM_KING")

pcm.browserViewController { (event) in
    
}

// Start again at any time
pcm.start() {
    // Do something when finished starting the session
}



// MARK: - Inviting peers/ Handling invitations

pcm.listenOn({ (event: PeerConnectionEvent) in
    
    switch event {
    case .foundPeer(let peer):
        print("Found peer \(peer.displayName)")
    
        // This is already handled if you initialize the PeerConnectionManager
        // with PeerConnectionType.automatic.
    
        // Invite peer to your session easily
        pcm.invitePeer(peer)
    
        // Invite peers with context data
        let someInfoAboutSession = [
            "thisSession" : "isCool"
        ]
        let sessionContextData = NSKeyedArchiver.archivedData(withRootObject: someInfoAboutSession)
        pcm.invitePeer(peer, withContext: sessionContextData, timeout: 10)
        
    case .lostPeer(let peer):
        print("Lost peer \(peer.displayName)")
        
    case .receivedInvitation(let peer, let context, let invitationHandler):
        print("\(peer.displayName) invited you to join their session")
        
        var shouldJoin = false
        
        defer {
            invitationHandler(shouldJoin)
        }
        
        guard let context = context,
            let invitationContext = NSKeyedUnarchiver.unarchiveObject(with: context) as? [String:String],
            let isItCool = invitationContext["thisSession"]
            else { return }
        
        shouldJoin = (isItCool == "isCool")
        
    default: break
    }
}, withKey: "connectAutomaticallyIfItsCool")

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
let event: [String: Any] = [
    "eventKey" : Date()
]

// Sends to all connected peers
pcm.sendEvent(event)

// Use this to access the connectedPeers
let connectedPeers: [Peer] = pcm.connectedPeers

if let somePeerThatIAmConnectedTo = connectedPeers.first {
    
    switch somePeerThatIAmConnectedTo.status {
    case .currentUser:
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
    
    
    let progress: [Peer:Progress?] = pcm.sendResourceAtURL(NSURL(string: "someurl")! as URL, withName: "resource-name", toPeers: [somePeerThatIAmConnectedTo]) { (error: Error?) in
        // Handle potential error
        print("Error: \(error)")
    }
}



// MARK: - Handling incoming events/notifications

// It is generally a good idea to configure your peer session before calling .start()

// Create an event listener
pcm.observeEventListenerFor("someEvent") { (eventInfo, peer) in
    
    print("Received some event \(eventInfo) from \(peer.displayName)")
    guard let date = eventInfo["eventKey"] as? Date else { return }
    print(date)
    
}
// or...
let eventListener: PeerConnectionEventListener = { event in
    
    switch event {
        
    case .ready: break
    case .started: break
    case .devicesChanged(let peer, let connectedPeers): break
    case .receivedData(let peer, let data): break
    case .receivedEvent(let peer, let eventInfo):
    
        print("Received some event \(eventInfo) from \(peer.displayName)")
        guard let date = eventInfo["eventKey"] as? Date else { return }
        print(date)
        
    case .receivedStream(let peer, let stream, let name): break
    case .startedReceivingResource(let peer, let name, let progress): break
    case .finishedReceivingResource(let peer, let name, let url, let error): break
    case .receivedCertificate(let peer, let certificate, let handler): break
    case .error(let error): break
    case .ended: break
    case .foundPeer(let peer): break
    case .lostPeer(let peer): break
    case .receivedInvitation(let peer, let context, let invitationHandler): break
    }
}

// Set up listeners
pcm.listenOn(eventListener, withKey: "someEvent")


// Add and remove listeners at any time
pcm.removeListenerForKey("someEvent")
pcm.listenOn(eventListener, withKey: "someEvent")

pcm.listenOn({ (event) in
    
    switch event {
    case .devicesChanged(let peer, let connectedPeers):
        
        // Get informed about changes in the peers connected to the current session
        switch peer.status {
        case .connected :
            print("\(peer.displayName) connected to session")
        case .connecting :
            print("\(peer.displayName) is attempting to connect")
        case .notConnected :
            print("\(peer.displayName) disconnected or was unable to connect")
        default : break
        }
    default : break
    }
    
}, withKey: "connectedDevicesChanged")

// Listen to streams
pcm.listenOn({ event in
    
    switch event {
    case .receivedStream(let peer, let stream, let name):
        print("Recieved stream with name: \(name) from peer: \(peer.displayName)")
        // Do something with input stream
        
    default: break
    }
    
}, withKey: "streamListener")

// Receiving resources
pcm.listenOn({ event in
    
    switch event {
    case .startedReceivingResource(let peer, let name, let progress):
        // Started receivng resource from peer
        print("Receiving resource with name: \(name) from peer: \(peer.displayName) with progress: \(progress)")
        
    case .finishedReceivingResource(let peer, let name, let url, let error):
        // Finished receiving resource from peer
        print("Finished receiving resource with name: \(name) from peer: \(peer.displayName) at url: \(url.path) with error: \(error)")
        
    default: break
    }
    
}, withKey: "resourceListener")



// You should always stop the connection manager when you are done with it.
// Starting a new manager without properly stopping other managers on the same device can
// result in undefined behavior.
pcm.stop()


// TODO: - Extend service with NSNetService and Bonjour C API for manually
//      configuring the PeerSession.
// TODO: - Add Testing

