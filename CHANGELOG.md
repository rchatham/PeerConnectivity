# Changelog

* **Unreleased** Add peer security configuration
  - New: `PeerSecurityConfiguration`, `PeerCertificatePolicy`, and `PeerInvitationPolicy` for explicit session security and invitation handling
  - New: `PeerDiscoveryInfo` support for advertised discovery metadata
  - New: `foundPeerWithDiscoveryInfo` event case in `PeerConnectionEvent`; callers with exhaustive switches should handle this case or include `default`
  - New: `PeerConnectivityUI` browser peer filtering with discovery metadata
  - Compatibility: `foundPeer` remains emitted alongside `foundPeerWithDiscoveryInfo`, so listeners should handle one discovery event to avoid processing the same peer twice
  - Compatibility: automatic non-manual invitation policies still emit `.receivedInvitation` for observation, but the event handler is a no-op and policy decisions remain authoritative
  - Compatibility: listener registration now observes future connection events only instead of replaying the responder's most recently stored event; state-oriented internal observables still replay their current value
  - New: `PeerConnectionError`; the Network backend now reports listener and browser failures, Local Network denial, and listener creation errors through `.error`
  - New: `PeerConnectionManager.setAdvertisingEnabled(_:)` toggles discoverability without ending the session or dropping connections on both backends
  - Network backend: `startBrowsingOnly()` no longer publishes a Bonjour service, and `.lostPeer` is now emitted when a peer's advertisement disappears (Bonjour removal results carry no TXT record, so peers are resolved by endpoint)
  - Network backend: app `discoveryInfo` is published in the Bonjour TXT record and surfaced in `.foundPeerWithDiscoveryInfo`; new `PeerConnectionManager.isValidNetworkDiscoveryInfo(_:)` and `PeerConnectionError.invalidDiscoveryInfo`
  - Network backend: invitations now carry `context`, honor `timeout`, and are admitted by the invitee's connection type and `invitationPolicy`; `.inviteOnly` and `.custom` apps must answer `.receivedInvitation`. Previously, inbound Network connections bypassed the policy
  - Network backend (wire-breaking): protocol version 2 adds invitation and two-sided admission frames; version 1 peers are rejected
  - New: `PeerConnectionNetworkSecurity.certificate(identity:)` for mutual TLS 1.3 under `.networkFramework`; peer certificates go through `certificatePolicy` and `.receivedCertificate`, and peers connect only after both sides accept
  - New: `sendData(_:toPeers:completion:)` and `sendMessage(_:toPeers:completion:)` report per-peer send failures on both backends (local processing, not delivery); `PeerConnectionError.peerNotConnected` for targeted peers without a Network connection
  - Network backend: discovery tracks at most 64 peers, and TCP keepalive detects dead peers in about 60 seconds; `.lostPeer` is no longer emitted for peers that were never reported found
  - Fixed: Network backend certificate mode no longer stalls connections when `trustd` is slow; the TLS verify block reads the peer chain from the TLS metadata instead of calling `SecTrustGetCertificateCount`
  - Packaging: the core target now links both Network.framework and MultipeerConnectivity.framework
  - New: `PeerConnectivityBluetooth` SwiftPM product with `PeerConnectionManager(serviceType:links:)`. `links: .bluetooth` is a Core Bluetooth backend so nearby peers connect with Wi-Fi off; `links: .all` runs Wi-Fi (Network framework) and Bluetooth at the same time. Every link takes the same `PeerConnectionNetworkSecurity` as the Network backend: plaintext, pre-shared key (Noise NNpsk0 with forward secrecy over Bluetooth) or certificates (Noise NN plus signed certificates over Bluetooth, trust left to `certificatePolicy`). A Bluetooth peer is lost after `lostPeerTimeout` (default 5 seconds) without an advertisement. Apps need `NSBluetoothAlwaysUsageDescription`; data streams and resource transfer are not supported
  - New: with `links: .all`, a peer reachable over both radios is connected over both and reported once: one `.foundPeer`, one connection, one invitation and one certificate decision per peer. It stays connected while either link is up, sends prefer Wi-Fi and fall back to Bluetooth (retrying a failed send on the other link), and messages that switch links may arrive out of order. A second link is admitted without asking only for a peer that is connected or was just admitted, and with certificates only if it presents the certificate the app accepted
  - New: `PeerConnectionBackend.bluetooth`, `PeerConnectionBackend.networkFrameworkAndBluetooth`, `PeerConnectionLinks` and `PeerBluetoothError`; callers with exhaustive switches over `PeerConnectionBackend` should handle the new cases or include `default`. Passing either new case to `init(serviceType:...backend:)` traps; use the Bluetooth product's initializer
  - Packaging: the internal transport seam now uses Swift `package` access so a transport can live in its own SwiftPM product; the Xcode project and podspec pass `-package-name PeerConnectivity`. No public API change
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
