
![PeerConnectivity](http://reidchatham.com/src/PeerConnectivity.png)


[![Platform: iOS 8+ / macOS 10.10+](https://img.shields.io/badge/platform-iOS%208%2B%20%7C%20macOS%2010.10%2B-blue.svg?style=flat)]()
[![Language: Swift 5](https://img.shields.io/badge/language-swift%205-f48041.svg?style=flat)](https://developer.apple.com/swift)
[![SwiftPM compatible](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg?style=flat)](https://swift.org/package-manager/)
[![License: MIT](http://img.shields.io/badge/license-MIT-lightgrey.svg?style=flat)]()

#### A functional wrapper for the MultipeerConnectivity framework. 

#### PeerConnectivity is meant to have a lightweight easy to use syntax, be extensible and flexible, and handle the heavy lifting and edge cases of the MultipeerConnectivity framework quietly in the background. 

#### Please open an issue or submit a pull request if you have any suggestions!

#### 🔌 Blog post [https://goo.gl/HJcMbE](https://goo.gl/HJcMbE)

## Installation

#### Swift Package Manager

Add PeerConnectivity as a Swift Package dependency:

```swift
.package(url: "https://github.com/rchatham/PeerConnectivity.git", from: "0.6.0")
```

Use the core networking product for UIKit-free peer connectivity:

```swift
.product(name: "PeerConnectivity", package: "PeerConnectivity")
```

Add the UI helper product only when you need UIKit browser view controller support:

```swift
.product(name: "PeerConnectivityUI", package: "PeerConnectivity")
```

CocoaPods and Carthage are no longer the recommended distribution paths for new releases.


## Creating/Stopping/Starting

```swift
var pcm = PeerConnectionManager(serviceType: "local")

// Start
pcm.start()

// Stop
//  - You should always stop the connection manager 
//    before attempting to create a new one
pcm.stop()

// Can join chatrooms using PeerConnectionType.automatic, .inviteOnly, and .custom
//  - .automatic : automatically searches and joins other devices with the same service type
//  - .inviteOnly : provides advertiser assistant behavior; import PeerConnectivityUI for browserViewController support
//  - .custom : no default behavior is implemented

// The manager can be initialized with a contructed peer representing the local user
// with a custom displayName

pcm = PeerConnectionManager(serviceType: "local", connectionType: .automatic, displayName: "I_AM_KING")

// Start again at any time
pcm.start() {
    // Do something when finished starting the session
}
```

## Browser UI

UIKit browser view controller support lives in the separate `PeerConnectivityUI` SwiftPM product:

```swift
import PeerConnectivity
import PeerConnectivityUI

let pcm = PeerConnectionManager(serviceType: "local", connectionType: .inviteOnly)
let browserViewController = pcm.browserViewController { event in
    switch event {
    case .didFinish, .wasCancelled, .none:
        break
    }
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


### Helpful links 

- Check out the [Demo project](https://github.com/rchatham/PeerConnectivity/tree/master/PeerConnectivityDemo) and [Playground](https://github.com/rchatham/PeerConnectivity/blob/master/PeerPlayground.playground/Contents.swift) for examples to help you take you're app to the next level!!!

- Read the [docs!](http://reidchatham.com/docs/PeerConnectivity/index.html)

