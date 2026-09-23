# Migrating an App from MultipeerConnectivity to Network.framework

PeerConnectivity now includes an experimental Network.framework backend for apps evaluating a migration away from MultipeerConnectivity (MC). This guide is for app developers integrating the existing public `PeerConnectionManager` API; it is not a promise that the two Apple frameworks behave identically.

## Current release posture

- `.multipeerConnectivity` remains the default. Existing initializer calls keep their current runtime behavior.
- `.networkFramework` is an explicit, experimental opt-in requiring iOS 13.0+ or macOS 10.15+.
- Opt in only for a bounded reliable-message use case that you can validate on your devices and networks.
- Keep an app-controlled rollback to `.multipeerConnectivity` while Network remains experimental.
- **There is no direct wire interoperability between the backends.** An MC peer cannot discover, connect to, or exchange PeerConnectivity messages with a Network peer. All participants in one session must select the same backend. PeerConnectivity includes no bridge, relay, or protocol translator.

The authoritative readiness gates for stable opt-in, a future default change, and eventual MC removal are in [NetworkMigrationReadinessAudit.md](NetworkMigrationReadinessAudit.md). Do not infer production readiness or a scheduled default switch from the presence of the opt-in.

## 1. Confirm that your use case fits

The Network backend currently supports:

- Bonjour advertising and discovery;
- automatic connections and custom, app-initiated peer selection;
- reliable `Data` and typed `PeerMessage` exchange;
- targeted sends and multi-peer broadcast; and
- TLS with an app-provisioned pre-shared key (PSK).

Keep using MC if your app currently requires any of these behaviors:

- `MCBrowserViewController` or `MCAdvertiserAssistant` behavior supplied by the system;
- `sendDataStream(streamName:toPeer:)` or `.receivedStream`;
- `sendResourceAtURL(_:withName:toPeers:withCompletionHandler:)` or resource receive events;
- direct access to `multipeerSession`;
- MC certificate callbacks; or
- MC invitation context, timeout, or inbound approval semantics.

Network stream sends throw an unsupported-operation error. Network resource sends return `nil` progress and complete with an unsupported-operation error. The corresponding receive events are never emitted. Use bounded `Data` or `PeerMessage` payloads, or retain MC for those sessions.

## 2. Deployment and app-target requirements

### Platforms

The package supports iOS 13.0+ and macOS 10.15+. Requesting `.networkFramework` on an unsupported OS is a programmer error and terminates during manager initialization; there is no silent MC fallback. Keep your deployment target and any runtime availability paths consistent with that contract.

### Service type

Continue passing the same bare MC-compatible service type where possible:

```swift
guard PeerConnectionManager.isValidServiceType("local") else {
    preconditionFailure("Invalid PeerConnectivity service type")
}
```

A bare `serviceType: "local"` maps to the TCP Bonjour type `_local._tcp`. A bare `"test-service"` maps to `_test-service._tcp`. Service types must be 1–15 characters, contain only lowercase ASCII letters, numbers, and hyphens, contain at least one letter, and cannot start or end with a hyphen or contain consecutive hyphens.

### Info.plist

Add local-network privacy metadata to the **adopting app target's built `Info.plist`**, not the package or framework plist:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Discover and connect to nearby devices running this app.</string>
<key>NSBonjourServices</key>
<array>
    <string>_local._tcp</string>
</array>
```

Use purpose text that accurately describes the user-facing feature and declare every service type the app uses. This implementation advertises TCP, not UDP. These are app metadata keys, not entitlements; the backend does not itself require the restricted multicast entitlement.

Treat Local Network denial as a real unavailable state. An empty result after denial does not prove that no peers exist. The current experimental backend does not yet expose every listener, browser, permission, or connection failure through a complete public error contract, so the app must avoid presenting silence as a definitive “no peers” result.

## 3. Change manager construction

### Before: current/default MC behavior

This is an actual supported initializer and remains equivalent to explicitly selecting MC:

```swift
let manager = PeerConnectionManager(
    serviceType: "local",
    connectionType: .automatic,
    displayName: "Alice",
    securityConfiguration: .encrypted,
    backend: .multipeerConnectivity
)

manager.start()
```

Omitting `backend` still defaults to `.multipeerConnectivity`:

```swift
let manager = PeerConnectionManager(serviceType: "local")
```

`PeerSecurityConfiguration` configures only the MC session. Requiring MC encryption without validating a peer identity does not by itself authenticate an individual peer.

### After: experimental Network opt-in

Provision high-entropy key bytes through your app, then pass them with the Network backend:

```swift
import Foundation
import PeerConnectivity

let secret : Data = try loadProvisionedNetworkPSK()
let manager = PeerConnectionManager(
    serviceType: "local",
    connectionType: .automatic,
    displayName: "Alice",
    backend: .networkFramework,
    networkSecurity: .preSharedKey(secret)
)

manager.start()
```

`networkSecurity` is ignored by MC. `securityConfiguration` is ignored by Network. Do not accidentally configure one while assuming it secures the other.

`.unauthenticated` uses plaintext TCP and exists only for diagnostics and migration compatibility. Do not use it for sensitive data. The default value remains `.unauthenticated` for source compatibility, which is another reason Network must remain an explicit choice rather than an implicit backend default.

## 4. Security and trust

For Network sessions, prefer `.preSharedKey` and:

1. Generate at least 32 random bytes (256 bits) with a cryptographically secure random-number generator.
2. Provision the key over an authenticated channel.
3. Keep it out of source, app bundles, process arguments, logs, screenshots, crash metadata, Bonjour TXT records, and invitation context.
4. Store it with platform-appropriate protection, scope it to one app/environment/group, and rotate it when membership changes or compromise is suspected.
5. Verify that matching keys connect and mismatched keys fail.

TLS-PSK provides confidentiality and integrity against outsiders and authenticates possession of a shared group secret. It does **not** authenticate an individual person, account, device, or installation. Any group member can claim another member's self-asserted identifier or display name.

Therefore:

- use `Peer.displayName` only as presentation text;
- do not authorize actions or build trustworthy audit records from display name or peer identifier alone;
- treat discovery metadata as public, unauthenticated routing/capability data; and
- keep sensitive, identity-dependent products on a separately reviewed identity layer or on the appropriate existing backend until the trust-model gates are complete.

See [NetworkTrustModelPlan.md](NetworkTrustModelPlan.md) for the exact threat model and future identity options.

## 5. Migrate connection behavior and UI

### Automatic mode

`.automatic` advertises, browses, and attempts connections on both backends. Network connections remain subject to protocol checks, security configuration, and fixed experimental limits (10-second handshake timeout, 16 pending connections, and 8 connected peers).

### Manual or invitation-driven flows

MC `.inviteOnly` can use framework-provided advertiser/browser UI. Network has no `MCBrowserViewController` or advertiser-assistant equivalent. Build app-owned UI with `PeerBrowserModel`, normally using `.custom` when selection must precede an outbound connection:

```swift
let manager = PeerConnectionManager(
    serviceType: "local",
    connectionType: .custom,
    displayName: "Alice",
    backend: .networkFramework,
    networkSecurity: .preSharedKey(secret)
)

let browserModel = PeerBrowserModel(manager: manager) { peers in
    // Main queue: update app-owned UIKit or SwiftUI discovery state.
}

browserModel.startObserving()
manager.start()

if let approvedPeer = browserModel.discoveredPeers.first {
    browserModel.invitePeer(approvedPeer)
}
```

Own loading, empty, permission/error, selection, cancellation, connection-progress, accessibility, and lifecycle states. Call `stopObserving()` when observation ends.

Important behavioral differences:

- Network `invitePeer(_:withContext:timeout:)` connects to the discovered endpoint; `context` and the caller-provided `timeout` are currently ignored.
- Network `.inviteOnly` does not reproduce MC invitation dialogs or inbound invitation-handler approval.
- Inbound Network connections are transport-accepted subject to protocol and security checks. App-owned outbound selection is not an inbound authorization boundary.
- `PeerConnectivityUI.browserViewController` returns `nil` for a Network-backed manager.

If user approval of every inbound peer is a product or security requirement, do not assume the current Network invitation UI provides it. Keep MC or add a separately designed, reviewed application protocol before migration.

## 6. Preserve application protocol compatibility

Backend selection and application protocol versioning are separate concerns. Use non-secret discovery metadata for coarse compatibility filtering and version your `PeerMessage` payloads or handshake at the app layer. Do not place credentials or personal data in discovery metadata.

During a mixed-version rollout:

- old and new app versions can communicate only when they select the same backend and support compatible app payloads;
- an old MC-only version cannot communicate directly with a new instance currently running Network;
- use cohorting, feature negotiation outside the peer wire, or an app-level backend selector so likely peers choose the same backend; and
- reject unsupported payload/protocol versions explicitly rather than decoding them as a previous format.

A dual-backend app may offer a setting or remote-configured choice, but one `PeerConnectionManager` session does not bridge the transports. Running both discovery domains also needs deliberate product behavior to avoid duplicate-looking peers and confusing connection state.

## 7. Test on physical devices

Simulator and local loopback coverage is useful for API flow, UI, framing, and regression checks, but it is not a production release gate. Validate the release build, or an equivalently signed build, on at least two supported physical devices.

- [ ] Inspect the built app's `Info.plist` for the purpose string and every `_service._tcp` entry.
- [ ] Start from clean installs and verify the Local Network prompt and copy.
- [ ] Test allow, deny, Settings recovery, and an actionable unavailable state.
- [ ] Test discovery, automatic or selected connection, bidirectional messages, disconnect, restart, and reconnect.
- [ ] Test matching, mismatched, rotated, and unavailable production-equivalent key material without leaking it.
- [ ] Test infrastructure Wi-Fi, including production guest/managed/VPN/firewall conditions.
- [ ] Separately test the required nearby peer-to-peer scenario with Wi-Fi enabled and without assuming a particular interface such as AWDL.
- [ ] Test background/foreground transitions, repeated start/stop, peer churn, capacity, and stale-peer cleanup.
- [ ] Record device models, OS versions, topology, permission state, backend, security mode, and results.

`includePeerToPeer` opts Network.framework into peer-to-peer link technologies; it does not guarantee Bluetooth, AWDL, a particular interface, discovery, or operation under every network policy.

## 8. Roll out safely

### Staged rollout

1. Inventory MC-only APIs, invitation assumptions, identity-dependent authorization, service types, app protocols, and required topologies.
2. Add app metadata and app-owned UI while the production path still uses MC.
3. Put backend selection behind a local feature flag or controlled configuration whose last-known-safe value is MC.
4. Enable Network only for internal/test cohorts that can coordinate backend selection on all peers.
5. Expand by device/OS/topology cohorts only after physical-device evidence is recorded.
6. Keep MC available through at least the experimental transition and define who can trigger rollback.

### Observability

Record operational events without secrets or sensitive peer metadata:

- selected backend and security mode (never key material);
- app protocol version, device/OS class, and coarse topology;
- Local Network permission/unavailable UI state where the app can determine it;
- discovery-to-connection timing, connection/disconnection counts, reconnects, and session duration;
- message counts/sizes and app-level acknowledgement latency where appropriate; and
- unsupported-operation, decode/version, and visible transport errors.

The public send APIs do not currently report every asynchronous Network send failure, and the Network error-state contract is incomplete. Use app-level acknowledgements/timeouts when the product needs delivery evidence; do not report a successful API call as proven remote receipt.

Define rollback thresholds before rollout—for example, permission recovery failures, discovery/connection success regression, elevated reconnect rates, message acknowledgement failure, crash regression, or topology-specific support incidents. Rollback means selecting `.multipeerConnectivity` on **all peers expected to communicate**, not changing only one endpoint.

## Migration checklist

- [ ] Confirm the app needs only the supported Network capability set.
- [ ] Keep `.multipeerConnectivity` as the default/fallback while Network is experimental.
- [ ] Raise/confirm deployment targets and audit availability handling.
- [ ] Validate every service type and add matching app-target Bonjour declarations.
- [ ] Add and test the Local Network purpose string and denial/recovery UX.
- [ ] Provision a 32+-byte CSPRNG-generated PSK; do not ship sensitive use on plaintext TCP.
- [ ] Remove trust decisions based only on display names or self-asserted peer identifiers.
- [ ] Replace MC browser/assistant UI with app-owned discovery and selection where needed.
- [ ] Audit invitation context, timeout, and inbound approval assumptions.
- [ ] Replace stream/resource dependencies with bounded messages or retain MC.
- [ ] Version app messages and plan same-backend behavior for mixed app versions.
- [ ] Complete and record the physical-device/topology/security matrix.
- [ ] Add backend-safe observability, rollout cohorts, rollback thresholds, and ownership.
- [ ] Re-read the readiness audit before changing production status or defaults.

## Deeper documentation

- [NetworkBackendGuide.md](NetworkBackendGuide.md) — detailed setup, API matrix, demo arguments, topology caveats, and physical-device checklist.
- [NetworkMigrationReadinessAudit.md](NetworkMigrationReadinessAudit.md) — authoritative stable/default/removal gates and risk register.
- [NetworkTrustModelPlan.md](NetworkTrustModelPlan.md) — current PSK boundary, insider spoofing threat model, and future trust options.
- [NetworkFrameworkMigrationPlan.md](NetworkFrameworkMigrationPlan.md) — architecture and staged implementation history.
- [NetworkMigrationPRPlan.md](NetworkMigrationPRPlan.md) — implementation stack and sequencing history.
- [DemoSecurityAndInteroperabilityPlan.md](DemoSecurityAndInteroperabilityPlan.md) — demo security and interoperability decisions.
- [PeerConnectivityDemo/README.md](PeerConnectivityDemo/README.md) — hands-on backend, invitation, security, and validation flow.
