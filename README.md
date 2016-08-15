PeerConnectivity
================

[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

####A functional wrapper for the MultipeerConnectivity framework. 

######PeerConnectivity is meant to have a lightweight easy to use syntax, be extensible and flexible, and handle the heavy lifting and edge cases of the MultipeerConnectivity framework quietly in the background. 

######Please open an issue or submit a pull request if you have any suggestions!

######Check out the Playground!


### Installation

####Cocoapods

```ruby
pod 'PeerConnectivity'
```

####Carthage

```ruby
github "rchatham/PeerConnectivity"
```


### Creating/Stopping/Starting

```swift
var pcm = PeerConnectionManager(serviceType: "local")

// Start
pcm.start()

// Stop
//  - You should always stop the connection manager 
//    before attempting to create a new one
pcm.stop()

// Can join chatrooms using PeerConnectionType.Automatic, .InviteOnly, and .Custom
//  - .Automatic : automatically searches and joins other devices with the same service type
//  - .InviteOnly : provides a browserViewController and invite alert controllers
//  - .Custom : no default behavior is implemented

// The manager can be initialized with a contructed peer representing the local user
// with a custom displayName

pcm = PeerConnectionManager(serviceType: "local", connectionType: .Automatic, displayName: "I_AM_KING")

// Start again at any time
pcm.start() {
    // Do something when finished starting the session
}
```

### Sending Events to Peers

```swift
let event: [String: AnyObject] = [
    "EventKey" : NSDate()
]

// Sends to all connected peers
pcm.sendEvent(event)


// Use this to access the connectedPeers
let connectedPeers: [Peer] = pcm.connectedPeers

// Events can be sent to specific peers
if let somePeerThatIAmConnectedTo = connectedPeers.first {
   pcm.sendEvent(event, toPeers: [somePeerThatIAmConnectedTo])
}
```

### Listening for Events

```swift
// Listen to an event
pcm.listenOn(eventReceived: { (peer: Peer, eventInfo: [String:AnyObject]) in
    print("Received some event \(eventInfo) from \(peer.displayName)")
    
    guard let date = eventInfo["EventKey"] as? NSDate else { return }
    print(date)
}, withKey: "SomeEvent")

// Stop listening to an event
pcm.removeListenerForKey("SomeEvent")
```

###Initializer

```swift
init(serviceType: ServiceType, 
  connectionType: PeerConnectionType = .Automatic, 
     displayName: String = UIDevice.currentDevice().name)
```

###Properties

```swift
connectionType : PeerConnectionType { get }

peer : Peer { get }

connectedPeers : [Peer] { get }

displayNames : [String] { get }

foundPeers: [Peer] { get }
```

###Methods

```swift
start(completion: (Void->Void)? = nil)

browserViewController(callback: PeerBrowserViewControllerEvent->Void) -> UIViewController?

invitePeer(peer: Peer, withContext context: NSData? = nil, timeout: NSTimeInterval = 30)

sendData(data: NSData, toPeers peers: [Peer] = [])

sendEvent(eventInfo: [String:AnyObject], toPeers peers: [Peer] = [])

sendDataStream(streamName name: String, toPeer peer: Peer) throws -> NSOutputStream

sendResourceAtURL(resourceURL: NSURL,
                                withName name: String,
                                toPeers peers: [Peer] = [],
             withCompletionHandler completion: ((NSError?) -> Void)? ) -> [Peer:NSProgress?]
             
refresh(completion: (Void->Void)? = nil)

stop()
```

#####In addition to these methods there is a full range of listeners that give you total control over the entire range of MultipeerConnectivity options.

```swift
listenOn(ready ready: ReadyListener = { _ in },
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
        withKey key: String) -> PeerConnectionManager
        
removeListenerForKey(key: String)

removeAllListeners()
```

###Listener Signatures

```swift
typealias ReadyListener = Void->Void
typealias StartListener = Void->Void
typealias SessionEndedListener = Void->Void
typealias DevicesChangedListener = (peer: Peer, connectedPeers: [Peer])->Void
typealias EventListener = (peer: Peer, eventInfo: [String:AnyObject])->Void
typealias DataListener = (peer: Peer, data: NSData)->Void
typealias StreamListener = (peer: Peer, stream: NSStream, name: String)->Void
typealias StartedReceivingResourceListener = (peer: Peer, name: String, progress: NSProgress)->Void
typealias FinishedReceivingResourceListener = (peer: Peer, name: String, url: NSURL, error: NSError?)->Void
typealias CertificateReceivedListener = (peer: Peer, certificate: [AnyObject]?, handler: (Bool) -> Void)->Void
typealias ErrorListener = (error: PeerConnectionError)->Void
typealias FoundPeerListener = (peer: Peer)->Void
typealias LostPeerListener = (peer: Peer)->Void
typealias ReceivedInvitationListener = (peer: Peer, withContext: NSData?, invitationHandler: (Bool) -> Void)->Void
```
