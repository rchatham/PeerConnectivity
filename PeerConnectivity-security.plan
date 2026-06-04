# PeerConnectivity Security Improvements Plan

## Goal

Add practical, well-documented security abstractions around MultipeerConnectivity features that PeerConnectivity currently omits or weakens, while preserving backward compatibility for existing users.

## Current State

- `PeerSession` creates `MCSession` with `securityIdentity: nil` and `encryptionPreference: .optional`.
- `MCSessionDelegate.session(_:didReceiveCertificate:fromPeer:certificateHandler:)` is surfaced as `.receivedCertificate`.
- `PeerConnectionManager` currently installs an internal listener that always calls `handler(true)` for certificate events.
- `.automatic` mode auto-invites found peers and auto-accepts incoming invitations.
- `MCNearbyServiceAdvertiser` and `MCAdvertiserAssistant` use `discoveryInfo: nil`.
- Browser receives `discoveryInfo`, but `PeerBrowserEvent.foundPeer` discards it.
- `invitePeer(_:withContext:timeout:)` and `.receivedInvitation(peer:withContext:invitationHandler:)` already expose invitation context.
- Service type and display name constraints are documented but not validated.

## Design Principles

1. Preserve existing initializer behavior where possible.
2. Prefer explicit security configuration over event-listener side effects.
3. Make insecure defaults visible in documentation.
4. Avoid overbuilding certificate generation/keychain helpers in the first pass.
5. Treat discovery info, display names, and invitation context as public or unauthenticated metadata unless documented otherwise.
6. Keep implementation aligned with the existing Observable/EventProducer architecture.

## Phase 1 — Session Security Configuration

### Add `PeerSecurityConfiguration`

Proposed API:

```swift
public struct PeerSecurityConfiguration {
    public var encryptionPreference : MCEncryptionPreference
    public var securityIdentity : [Any]?
    public var certificatePolicy : PeerCertificatePolicy

    public static let `default` = PeerSecurityConfiguration(
        encryptionPreference: .optional,
        securityIdentity: nil,
        certificatePolicy: .acceptAll
    )

    public static let encrypted = PeerSecurityConfiguration(
        encryptionPreference: .required,
        securityIdentity: nil,
        certificatePolicy: .acceptAll
    )
}
```

### Add `PeerCertificatePolicy`

Proposed API:

```swift
public enum PeerCertificatePolicy {
    case acceptAll
    case rejectAll
    case requireCertificate
    case custom((Peer, [Any]?, @escaping (Bool) -> Void) -> Void)
}
```

### Implementation Tasks

- Add security configuration to `PeerConnectionManager` initializer, defaulting to backward-compatible behavior.
- Pass security configuration into `PeerSession`.
- Update `PeerSession` to initialize `MCSession` with configured `securityIdentity` and `encryptionPreference`.
- Remove the hardcoded always-accept certificate listener from `PeerConnectionManager.init`.
- Handle `.didReceiveCertificate` directly using `PeerCertificatePolicy`.
- Keep `.receivedCertificate` event only if useful for custom/manual handling, but avoid competing calls to the same certificate handler.

### Tests

- Verify default config maps to `.optional`, `nil`, `.acceptAll`.
- Verify `.encrypted` maps to `.required`.
- Verify `.acceptAll`, `.rejectAll`, and `.requireCertificate` call the handler correctly.
- Verify `.custom` receives peer/certificate and controls acceptance.

## Phase 2 — Discovery Metadata

### Add Discovery Info Support

Proposed additions:

```swift
public typealias PeerDiscoveryInfo = [String:String]
```

- Add `discoveryInfo: PeerDiscoveryInfo?` to `PeerConnectionManager` init/config.
- Pass discovery info to `PeerAdvertiser` and `PeerAdvertiserAssisstant`.
- Preserve browser-provided discovery info in internal browser events.
- Surface discovery info publicly.

Possible public event shape:

```swift
case foundPeer(peer: Peer, discoveryInfo: PeerDiscoveryInfo?)
case nearbyPeersChanged(foundPeers: [Peer])
```

Alternative non-breaking approach:

- Keep existing `.foundPeer(peer:)`.
- Add a new event:

```swift
case foundPeerWithDiscoveryInfo(peer: Peer, discoveryInfo: PeerDiscoveryInfo?)
```

### Documentation Notes

Document that discovery info is advertised over Bonjour TXT records and should not contain secrets, tokens, emails, stable user IDs, or sensitive device information.

Good examples:

- Protocol version
- Non-secret capability flags
- Room/session label that is not secret

## Phase 3 — Invitation Policy

### Add Invitation Policy

Proposed API:

```swift
public enum PeerInvitationPolicy {
    case manual
    case acceptAll
    case rejectAll
    case custom((Peer, Data?) -> Bool)
}
```

### Implementation Tasks

- Add invitation policy to manager/config.
- In `.automatic`, replace blind accept with policy-based accept.
- Preserve `.receivedInvitation` for manual/custom modes.
- Consider typed Codable helpers for invitation context later.

### Security Notes

Invitation context is received before session establishment and should be considered unauthenticated. It can support pairing flows, protocol negotiation, and signed challenges, but should not carry raw secrets.

## Phase 4 — Validation and Privacy Hardening

### Service Type Validation

Apple constraints:

- Up to 15 characters.
- ASCII lowercase letters, numbers, and hyphen.
- Bonjour-style service type.

Possible API:

```swift
public static func isValidServiceType(_ serviceType: String) -> Bool
```

Later option:

```swift
public struct PeerServiceType {
    public let rawValue : String
}
```

### Display Name Validation

- Validate 63-byte UTF-8 maximum for `MCPeerID(displayName:)`.
- Document that display names are visible to nearby peers.
- Consider adding an anonymous/random display-name helper.
- Reconsider UI convenience default using `UIDevice.current.name`, since that may reveal personal names.

## Phase 5 — UI Filtering

In `PeerConnectivityUI`, expose `MCBrowserViewControllerDelegate.browserViewController(_:shouldPresentNearbyPeer:withDiscoveryInfo:)`.

Use cases:

- Hide peers with incompatible protocol versions.
- Hide peers lacking required advertised capabilities.
- Hide peers outside the intended app room/session.

## Suggested Initial Implementation Scope

Start with Phase 1 only:

1. Add `PeerSecurityConfiguration`.
2. Add `PeerCertificatePolicy`.
3. Thread config into `PeerSession`.
4. Replace hardcoded certificate acceptance.
5. Add focused tests.
6. Update docs/API comments.

This provides the largest security improvement with the least API churn.

## Open Questions

1. Should the default remain `.optional + acceptAll` for backward compatibility, or should the next release default to `.required`?
2. Should `.receivedCertificate` remain a public event, or should certificate handling move entirely to `PeerCertificatePolicy.custom`?
3. Should discovery info be added as a new event to avoid breaking existing switch statements?
4. Should service type validation fail initialization, log warnings, or be exposed only as a helper?
5. Should the iOS UI convenience initializer continue to use `UIDevice.current.name` by default?
