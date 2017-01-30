
![PeerConnectivity](http://reidchatham.com/src/PeerConnectivity.png)


[![Platform: iOS 8+](https://img.shields.io/badge/platform-iOS%208%2B-blue.svg?style=flat)]()
[![Language: Swift 3](https://img.shields.io/badge/language-swift3-f48041.svg?style=flat)](https://developer.apple.com/swift)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
[![Cocoapods compatible](https://cocoapod-badges.herokuapp.com/v/PeerConnectivity/badge.png)](https://cocoapods.org/pods/PeerConnectivity)
[![Docs](https://img.shields.io/cocoapods/metrics/doc-percent/PeerConnectivity.svg)](http://cocoadocs.org/docsets/PeerConnectivity)
[![License: MIT](http://img.shields.io/badge/license-MIT-lightgrey.svg?style=flat)]()

#### A functional wrapper for the MultipeerConnectivity framework. 

#### PeerConnectivity is meant to have a lightweight easy to use syntax, be extensible and flexible, and handle the heavy lifting and edge cases of the MultipeerConnectivity framework quietly in the background. 

##### Please open an issue or submit a pull request if you have any suggestions!

##### Check out the Playground!

#### Blog post [https://goo.gl/HJcMbE](https://goo.gl/HJcMbE)

#### Read the [docs!](http://reidchatham.com/docs/PeerConnectivity/Classes/PeerConnectionManager.html)


## Installation

The easiest way to get started is to use [CocoaPods](http://cocoapods.org/). Just add the following line to your Podfile:

```ruby
pod 'PeerConnectivity', '~> 0.5.4'
```

#### Carthage

```ruby
github "rchatham/PeerConnectivity"
```


## Creating/Stopping/Starting

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

## Sending Events to Peers

```swift
let event: [String: Any] = [
    "EventKey" : Date()
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

## Listening for Events

```swift
// Listen to an event
pcm.observeEventListenerForKey("someEvent") { (eventInfo, peer) in
    
    print("Received some event \(eventInfo) from \(peer.displayName)")
    guard let date = eventInfo["eventKey"] as? Date else { return }
    print(date)
    
}

// Stop listening to an event
pcm.removeListenerForKey("SomeEvent")
```

## Acknowledgments

Icon from the [Noun Project](https://thenounproject.com/search/?q=circle+people&i=125108).
