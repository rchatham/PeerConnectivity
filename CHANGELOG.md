# Changelog

* **Unreleased** Add peer security configuration
  - New: `PeerSecurityConfiguration`, `PeerCertificatePolicy`, and `PeerInvitationPolicy` for explicit session security and invitation handling
  - New: `PeerDiscoveryInfo` support for advertised discovery metadata
  - New: `foundPeerWithDiscoveryInfo` event case in `PeerConnectionEvent`; callers with exhaustive switches should handle this case or include `default`
  - New: `PeerConnectivityUI` browser peer filtering with discovery metadata
  - Compatibility: `foundPeer` remains emitted alongside `foundPeerWithDiscoveryInfo`, so listeners should handle one discovery event to avoid processing the same peer twice
  - Compatibility: automatic non-manual invitation policies still emit `.receivedInvitation` for observation, but the event handler is a no-op and policy decisions remain authoritative

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
