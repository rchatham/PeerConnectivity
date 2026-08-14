# Changelog

* **Unreleased** Add peer security configuration
  - New: `PeerSecurityConfiguration`, `PeerCertificatePolicy`, and `PeerInvitationPolicy` for explicit session security and invitation handling
  - New: `PeerDiscoveryInfo` support for advertised discovery metadata
  - New: `foundPeerWithDiscoveryInfo` event case in `PeerConnectionEvent`; callers with exhaustive switches should handle this case or include `default`
  - New: `PeerConnectivityUI` browser peer filtering with discovery metadata
  - Compatibility: `foundPeer` remains emitted alongside `foundPeerWithDiscoveryInfo`, so listeners should handle one discovery event to avoid processing the same peer twice
  - Compatibility: automatic non-manual invitation policies still emit `.receivedInvitation` for observation, but the event handler is a no-op and policy decisions remain authoritative
  - Compatibility: listener registration now observes future connection events only instead of replaying the responder's most recently stored event; state-oriented internal observables still replay their current value
  - Packaging: the core target now links both Network.framework and MultipeerConnectivity.framework
  - Tooling: the Swift package manifest uses Swift tools 6.0, so SwiftPM consumers need a Swift 6 toolchain (Xcode 16 or newer); the library remains compiled in Swift 5 language mode
  - Platforms: the minimum supported versions increase to iOS 13 and macOS 10.15; CocoaPods consumers need an Xcode version with those platform SDKs (Xcode 11 or newer)

* **0.7.0** Fixed deprecated NSKeyedUnarchiver and added modern type-safe messaging API
  - Fixed: Replaced deprecated `NSKeyedUnarchiver.unarchiveObject(with:)` with secure coding API
  - New: `PeerMessage` protocol for type-safe, Codable-based messaging
  - New: `sendMessage(_:toPeers:)` method for sending typed messages
  - New: `receivedMessage` event case in `PeerConnectionEvent`
  - New: `observeMessages(ofType:forKey:listener:)` for type-safe message listening
  - Deprecated: `sendEvent(_:toPeers:)` - use `sendMessage` instead
  - Deprecated: `observeEventListenerForKey(_:listener:)` - use `observeMessages` instead
  - Legacy APIs remain functional for backward compatibility

* **0.6.0** Updated to Swift 5.0

* **0.4.1** Swift 3 and iOS 10 compatibility

* **0.5.0** Changed instances of AnyObject to Any

* **0.5.1** Lowered iOS target to 8.0+

* **0.5.2** Added shortcut method for listening to events

* **0.5.3** Fixed documentation issue

* **0.5.4** Added listening for nearby devices changed
