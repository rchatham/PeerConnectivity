# Network Backend Guide

PeerConnectivity is migrating toward Apple's Network framework while preserving the existing MultipeerConnectivity-backed public API. The Network backend is available as an explicit opt-in migration path; the default backend remains `.multipeerConnectivity`.

## Release posture

The Network backend is not the default runtime path yet. Treat it as an experimental/beta backend for apps that can validate behavior in their own topology and OS/device matrix.

Use it when you need to evaluate the Network framework migration path for reliable local peer messaging. Continue using the default MultipeerConnectivity backend when you need the system-provided browser UI, stream transfer, resource transfer, stream/resource receive events, or proven production parity.

## Production app setup

`.networkFramework` requires iOS 13.0+ or macOS 10.15+. Before distributing an app that selects this backend, add the local-network privacy declarations to the **app target's built `Info.plist`**. Adding them to the package or framework plist does not configure an adopting app.

For a manager created with `serviceType: "local"`, use:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Discover and connect to nearby devices running this app.</string>
<key>NSBonjourServices</key>
<array>
    <string>_local._tcp</string>
</array>
```

Write a purpose string that accurately describes the app's user-facing feature. Declare every service type the app passes to a Network-backed manager. The current conversion is:

| `PeerConnectionManager` service type | Bonjour type to declare in `NSBonjourServices` |
|---|---|
| `"local"` | `_local._tcp` |
| `"test-service"` | `_test-service._tcp` |
| `"_test-service._tcp"` | `_test-service._tcp` |

Prefer the bare form, such as `"local"`, because it is compatible with the existing MultipeerConnectivity API. The Network backend adds the leading underscore and `._tcp` suffix. It uses TCP only, so do not add a corresponding `._udp` entry unless the adopting app separately advertises or browses that UDP service. The demo's complete example is in [`PeerConnectivityDemo/Info.plist`](PeerConnectivityDemo/Info.plist).

These values are app metadata, not entitlements. This backend's Bonjour-over-TCP implementation does not send custom multicast or broadcast packets, so it does not itself require the restricted multicast networking entitlement.

On systems that enforce local-network privacy, starting Bonjour discovery can present the system prompt using `NSLocalNetworkUsageDescription`. The user can deny access, and the app must treat unavailable discovery as a real runtime state rather than assuming that an empty peer list means no peers exist.

## Opt in

Create the manager with `backend: .networkFramework`:

```swift
import Foundation
import PeerConnectivity

let secret : Data = loadProvisionedNetworkPSK() // At least 32 random bytes; app-defined provisioning.
let manager = PeerConnectionManager(serviceType: "local",
    connectionType: .automatic,
    displayName: "Alice",
    backend: .networkFramework,
    networkSecurity: .preSharedKey(secret))

manager.start()
```

If `.networkFramework` is requested on an unsupported OS, initialization fails with a programmer-error `fatalError` instead of silently falling back to MultipeerConnectivity.

## Security model

Prefer `.preSharedKey` for every Network-backed app session:

```swift
let security = PeerConnectionNetworkSecurity.preSharedKey(secret)
let manager = PeerConnectionManager(serviceType: "local",
    backend: .networkFramework,
    networkSecurity: security)
```

`PeerConnectionNetworkSecurity.preSharedKey(_:)` configures TLS with a pre-shared key and requires exactly TLS 1.2. Apple's external PSK API, `sec_protocol_options_add_pre_shared_key`, supports PSK negotiation only in TLS 1.2, not TLS 1.3, so the transport pins both its minimum and maximum protocol versions to TLS 1.2. The modern minimum- and maximum-version setters are available across the Network backend's deployment range (iOS 13.0+ and macOS 10.15+). Peers must use the same non-empty key to complete the TLS handshake; negotiation failure does not fall back to another TLS version or to plaintext. This authenticates each endpoint only as a member of the key-sharing group, not as a particular person, device, account, or installation.

Guidance for app-managed secrets:

- Generate at least 256 random bits (32 bytes) with a cryptographically secure random-number generator. Do not use a password, passphrase, display name, service name, UUID text, predictable token, or demo string.
- Provision the key over an authenticated channel; keep it out of source, logs, Bonjour metadata, and the application bundle; store it with platform-appropriate protection.
- Scope the key to one app/environment and authorization group. Do not reuse it across unrelated protocols or groups.
- Rotate the key when membership changes or compromise is suspected.
- Treat every holder of the shared key as equally authorized under this mode.
- Treat Bonjour TXT metadata (`pc-id`, `pc-name`, `pc-v`, and app `discoveryInfo`) as routing/discovery metadata only. It is not a trust assertion.

### Discovery info

App `discoveryInfo` is published in the TXT record beside the reserved `pc-` keys and surfaces in `.foundPeerWithDiscoveryInfo` on browsing peers.
- Validate it with `PeerConnectionManager.isValidNetworkDiscoveryInfo(_:)`: printable-ASCII keys without `=`, no `pc-` prefix in any case, and at most 255 bytes per `key=value` entry. Keep the whole record small (under about 400 bytes).
- Invalid info fails closed: advertising does not start, and `.error(PeerConnectionError.invalidDiscoveryInfo)` is emitted.
- On the browsing side, remote reserved or malformed entries are dropped. A peer with no app entries reports `nil`, matching MultipeerConnectivity.
- Discovery info is public and unauthenticated. Never put secrets in it.

### Certificate mode

`PeerConnectionNetworkSecurity.certificate(identity:)` authenticates individual peers with mutual TLS 1.3. Each peer presents its own `SecIdentity`, and connections fail unless the remote peer presents a certificate too. Trust is decided by your existing `PeerSecurityConfiguration.certificatePolicy`:

```swift
let configuration = PeerSecurityConfiguration(encryptionPreference: .required,
    securityIdentity: nil,
    certificatePolicy: .custom { peer, chain, decide in
        // chain is [SecCertificate], leaf first. Pin it, or check it against your trust store.
        decide(isTrusted(leaf: chain?.first, for: peer))
    })
let manager = PeerConnectionManager(serviceType: "local",
    securityConfiguration: configuration,
    backend: .networkFramework,
    networkSecurity: .certificate(identity: localIdentity))
```

How it works:

1. TLS 1.3 completes only if both peers present a certificate and prove they hold its private key. System trust evaluation is bypassed so self-signed and app-issued certificates work. **Trust is entirely your policy's decision.**
2. After the identity handshake, the policy receives the peer and its certificate chain. `.receivedCertificate` is emitted for observation, matching MultipeerConnectivity.
3. On accept, the peer sends an `admitted` frame. A peer is reported connected only after **both** sides have accepted each other, so neither side can send data the other would drop. On reject, the timeout, or a protocol violation, the connection is canceled and nothing is reported.
4. The policy must decide within the 10-second handshake timeout. Repeated or late decisions are ignored.

Binding responsibility: the library binds the certificate to the *connection*, but the handshake identifier and display name are still self-asserted. With `.acceptAll` or `.requireCertificate`, any certificate holder is accepted and can claim any name. Use `.custom` and bind the certificate to the peer you expect, for example with a pinned-fingerprint store keyed by identifier. Certificate-mode peers interoperate only with other certificate-mode peers.

`.unauthenticated` is plaintext TCP. It remains available only for migration compatibility and diagnostics and must not be used for sensitive data.

Current limitation (PSK mode): TLS-PSK authenticates membership in the shared-key group; it does not bind the self-asserted handshake identifier or display name to an individual credential. Any member can claim another member's display name or identifier, so apps must not use `Peer.displayName` or the internal transport identifier as an authorization principal or trustworthy audit identity. Apps that need stronger identity guarantees should keep the Network backend opt-in until a stricter trust model is added.

See [NetworkTrustModelPlan.md](NetworkTrustModelPlan.md) for the insider spoofing threat model, exact PSK requirements, and future options including HKDF-derived scoped/pairwise keys, signed per-peer identity binding, certificate/pinning mode, and an app-provided verifier.

## Connection modes

### `.automatic`

Supported. Peers advertise and browse for the same service type, then attempt to connect automatically.

### `.custom`

Supported for app-owned peer selection. `PeerBrowserModel` is the supported Network replacement foundation for `MCBrowserViewController` during this migration phase. It tracks discovered peers and connection status without prescribing UIKit or SwiftUI presentation.

For example, an app-owned table view controller can bind the model to its own state and invite only after selection:

```swift
private var discoveredPeers : [Peer] = []
private lazy var browserModel = PeerBrowserModel(manager: manager) { [weak self] peers in
    self?.discoveredPeers = peers
    self?.tableView.reloadData() // Callback is delivered on the main queue.
}

override func viewDidLoad() {
    super.viewDidLoad()
    browserModel.startObserving()
    manager.start()
}

override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    browserModel.invitePeer(discoveredPeers[indexPath.row])
}
```

Own selection, empty/error states, accessibility, styling, and the model lifecycle in the app. Call `stopObserving()` when observation should end; the model also stops observing on deinitialization.

### Invitations

Network invitations follow the same contract as MultipeerConnectivity:

- `invitePeer(_:withContext:timeout:)` connects to the discovered peer and sends an invitation carrying `context`. Treat the context as public, unauthenticated metadata, as under MC. It is limited to 64 KiB.
- The invited peer holds the connection as pending and applies its connection type and `invitationPolicy`, exactly like an MC advertiser:
  - In `.automatic` mode, the policy decides (`.acceptAll`, `.rejectAll`, `.custom`), or `.manual` surfaces it.
  - In `.inviteOnly` and `.custom` modes, `.receivedInvitation(peer:withContext:invitationHandler:)` is always emitted, and the app must call the handler.
- Pending peers never appear in `connectedPeers` and never emit `devicesChanged(.connected)`. A peer is reported connected only after both sides have admitted each other.
- Declining sends a `declined` frame and closes the connection.
- `timeout` bounds how long both sides keep the invitation pending, capped at 120 seconds. Responses after the timeout are ignored.

Wire compatibility: invitations are part of Network protocol version 2. Version 1 peers, built from earlier commits of this experimental backend, are rejected during the handshake. They cannot be discovered by or connect to version 2 peers.

### `.inviteOnly`

The built-in MultipeerConnectivity advertiser assistant/browser UI is not available for the Network backend. Network-backed apps should provide their own UI using `.foundPeer`, `.lostPeer`, and `invitePeer`, and must answer `.receivedInvitation`. There is no system invitation dialog.

`PeerConnectivityUI.browserViewController` returns `nil` for Network-backed managers.

## Browser UI decision

A reusable SwiftUI or UIKit Network browser is intentionally deferred. Peer selection is product-specific, and the migration does not yet have enough app usage to establish stable shared behavior for selection, cancellation, connection progress, errors, accessibility, or presentation. Adding that surface now would increase UI and compatibility scope while the Network backend remains opt-in.

`PeerBrowserModel` is therefore the supported app-owned UI foundation for this phase. The MultipeerConnectivity-only `MCBrowserViewController` compatibility path remains unchanged, and no backend default changes as part of this decision. A reusable component can be reconsidered after app-owned integrations validate common requirements.

## API support matrix

| API / behavior | MultipeerConnectivity backend | Network backend |
|---|---:|---:|
| Default backend | ✅ | ❌ opt-in only |
| `.automatic` discovery/connect | ✅ | ✅ |
| `.custom` + app-owned `invitePeer` | ✅ | ✅ |
| `.inviteOnly` built-in browser UI | ✅ | ❌ app-owned UI required |
| Invitation `context` / `timeout` / `invitationPolicy` | ✅ | ✅ protocol v2 two-sided admission |
| `sendData` | ✅ | ✅ |
| `sendMessage` / `observeMessages` | ✅ | ✅ |
| Large framed messages | ✅ via MC | ✅ via TCP framing |
| Multi-peer broadcast | ✅ | ✅ bounded local E2E coverage |
| Disconnect/reconnect after peer restart | ✅ | ✅ bounded local E2E coverage |
| `sendDataStream` | ✅ | ❌ MultipeerConnectivity-only; throws unsupported-operation error |
| `sendResourceAtURL` | ✅ | ❌ MultipeerConnectivity-only; returns `nil` progress and reports an unsupported-operation error |
| `.receivedStream` | ✅ | ❌ MultipeerConnectivity-only; never emitted |
| `.startedReceivingResource` / `.finishedReceivingResource` | ✅ | ❌ MultipeerConnectivity-only; never emitted |
| `multipeerSession` | ✅ | ❌ programmer error |
| TLS-PSK transport security | MC-managed | ✅ TLS 1.2 only with `.preSharedKey` |
| Certificate identities + `certificatePolicy` | ✅ | ✅ mutual TLS 1.3 with `.certificate(identity:)` |

## Sending data and messages

The Network backend supports reliable `Data` and typed `PeerMessage` exchange:

```swift
struct ChatMessage : PeerMessage, Codable, Equatable {
    let text : String
}

manager.observeMessages(ofType: ChatMessage.self, forKey: "chat") { message, peer in
    print("received \(message.text) from \(peer.displayName)")
}

let message = ChatMessage(text: "hello")
manager.sendMessage(message, toPeers: manager.connectedPeers)
```

### Send outcomes

The fire-and-forget overloads above remain best-effort. When a caller needs to know whether a send failed, use the completion overloads. They work on both backends:

```swift
try manager.sendMessage(message, toPeers: manager.connectedPeers) { failures in
    // Called once on the main queue. Empty means every send was accepted locally.
    for (peer, error) in failures {
        print("send to \(peer.displayName) failed: \(error)")
    }
}
```

Contract:

- Success means the **local networking stack processed** the send (Network `contentProcessed`, or `MCSession.send` not throwing). It does **not** confirm that the remote app received the data. Use an application-level acknowledgement message if you need delivery receipts.
- Under Network, each target peer is reported independently. A targeted peer with no registered connection fails with `PeerConnectionError.peerNotConnected`.
- MultipeerConnectivity reports one error per send call, so every target of a failed send is listed with that error.
- Broadcasting (`toPeers: []`) with no connected peers completes with no failures.
- `sendMessage(_:toPeers:completion:)` throws synchronously if the message cannot be encoded, and nothing is sent.

## Stream and resource compatibility decision

`sendDataStream`, `sendResourceAtURL`, `.receivedStream`, `.startedReceivingResource`, and `.finishedReceivingResource` remain MultipeerConnectivity-only APIs for the current Network backend. They are not deprecated because they remain supported when using `.multipeerConnectivity`, but selecting `.networkFramework` does not provide alternate stream or resource semantics.

This migration stack will not add a custom stream or file-transfer protocol. Network framework has no direct equivalents for the MultipeerConnectivity APIs, and emulating them would require new framing, flow-control, progress, cancellation, persistence, and protocol-versioning contracts beyond the reliable `Data` and `PeerMessage` transport being migrated.

Network-backed `sendDataStream` calls throw an unsupported-operation error. Network-backed `sendResourceAtURL` calls return `nil` progress for each requested peer and invoke the completion handler with an unsupported-operation error. The Network backend never emits the stream or resource receive events. Calls fail explicitly rather than silently changing transport behavior.

Apps that need to exchange bounded in-memory payloads should use `sendData` or `sendMessage`. Apps that require stream or resource transfer must keep those sessions on `.multipeerConnectivity`. A future, separately scoped feature may revisit file or streaming transport, but it is not a parity requirement for the current Network migration.

## Demo app

The expanded demo shows the active backend and lets you choose **Multipeer** or **Network**, **Automatic** or **Require Invitation**, and backend-specific security before starting. Choices are remembered per backend and disabled while networking runs. Multipeer maps **Compatible** to `.default` and **Require Encryption** to `.encrypted`; neither authenticates peers because the demo uses a nil identity and accepts all certificates, so it remains MITM-vulnerable. Network maps **Unauthenticated** to plain TCP and **TLS Shared Key** to `.preSharedKey` only after strict Base64 validation of at least 32 decoded bytes. Invalid TLS input blocks Start and never downgrades.

The same path can be selected with launch arguments:

- `PCNetworkBackend` — select `.networkFramework` instead of the default MultipeerConnectivity backend.
- `PCAutoStart` — start the manager on launch.
- `PCDisplayName <name>` — set a deterministic display name such as `Alice` or `Bob`.
- `PCNetworkPSKBase64 <value>` — in `#if DEBUG` builds only, select Network TLS and pass the value through the same strict validation as manual input.

Example arguments for two simulator or device instances:

```text
PCNetworkBackend PCNetworkPSKBase64 <test-base64> PCAutoStart PCDisplayName Alice
PCNetworkBackend PCNetworkPSKBase64 <test-base64> PCAutoStart PCDisplayName Bob
```

For **Require Invitation**, tap the enabled invite action for a discovered peer, wait for its status to become **Connected**, then enter and send a typed message or ping. Security remains independent from invitation flow; the manager continues to use `invitationPolicy: .acceptAll`. See [`PeerConnectivityDemo/README.md`](PeerConnectivityDemo/README.md) for the complete walkthrough.

The secure field and generated test key are in-memory only, are excluded from logs/status/accessibility/export, survive ordinary Stop for restart, and are dropped on Reset without claiming secure erasure. The process argument can be inspected by local tooling and is debug-only test convenience, never production provisioning. TLS-PSK authenticates group membership, not individual identity. Both peers must select the same backend because MultipeerConnectivity and Network.framework are not wire-compatible; the demo contains no bridge code.

## Errors

The Network backend reports problems through `.error(_:)` with `PeerConnectionError` values. MultipeerConnectivity keeps emitting its own errors.

| Error | Meaning |
|---|---|
| `.localNetworkAccessDenied(underlying:)` | The user denied Local Network access (iOS 14+). Discovery and advertising resume if access is granted in Settings. |
| `.browsingFailed(underlying:)` | The Bonjour browser failed. |
| `.advertisingFailed(underlying:)` | The listener failed to start or stopped, including creation errors. Creation errors are reported when the manager starts. |
| `.invalidDiscoveryInfo` | `discoveryInfo` cannot be published; advertising did not start. |
| `.peerNotConnected(_:)` | Returned in send-outcome completions for targeted peers without a connection. |

Individual connection failures do not produce `.error`. They surface as `devicesChanged` with `.notConnected`, as under MultipeerConnectivity.

## Network path and device caveats

PeerConnectivity sets `NWParameters.includePeerToPeer = true` on the parameters used by its Network listener, browser, and connections. Apple documents this as opting in to peer-to-peer link technologies, and more specifically describes the Network framework path as Apple peer-to-peer Wi-Fi. This is an opt-in, not a request for a particular interface or a guarantee that a peer-to-peer path will be selected.

Plan around these boundaries:

- Two devices on the same infrastructure Wi-Fi can communicate locally without internet access, provided the network permits client-to-client traffic and Bonjour. Guest-network isolation, managed-network policy, VPNs, and firewalls can prevent discovery or connection.
- Keep Wi-Fi enabled when validating peer-to-peer operation. Do not describe this backend as Bluetooth-only or as a Bluetooth LE transport; it has no Core Bluetooth API or explicit Bluetooth transport selection.
- AWDL is commonly used as shorthand for an Apple peer-to-peer Wi-Fi implementation detail. The public API used here exposes only `includePeerToPeer`; apps cannot require AWDL, select it, or infer from that flag which interface carried a connection.
- Radio state, device/OS combinations, network policy, and nearby interference can affect results. Enabling `includePeerToPeer` does not promise discovery under every topology.
- Stop managers, browsers, and connections when the feature is no longer in use. Apple notes that peer-to-peer Wi-Fi operation can affect network performance.

The simulator is useful for API flow, UI, and loopback automation, and it may discover local Bonjour services through the Mac's networking environment. It is not a production validation substitute: simulator privacy behavior and interfaces differ from a physical device, and it cannot establish confidence in on-device peer-to-peer Wi-Fi, radio-state, or Local Network permission behavior.

## Manual physical-device validation

Complete this checklist on the release build (or an equivalently signed build) before shipping the Network backend:

- [ ] Confirm the built app's `Info.plist` contains the intended `NSLocalNetworkUsageDescription` and every required `NSBonjourServices` value, such as `_local._tcp` for `serviceType: "local"`.
- [ ] Install cleanly on two supported physical devices so permission state is known; start networking and verify the Local Network prompt presents with the intended copy.
- [ ] Allow access on both devices, then verify discovery, invitation/automatic connection as applicable, bidirectional typed messages, disconnect, and reconnect.
- [ ] Deny Local Network access on one device and verify the app shows an actionable unavailable/permission state rather than hanging, crashing, or claiming no peers exist. Restore access in Settings and retest.
- [ ] Verify two devices on the supported infrastructure Wi-Fi topology, including the production router or managed network when relevant. Confirm the feature does not depend on internet reachability.
- [ ] Separately validate the product's required nearby peer-to-peer scenario with Wi-Fi enabled and without relying on the infrastructure path. Record device models and OS versions; do not infer the selected interface from success alone.
- [ ] Exercise app background/foreground transitions and stopping/restarting networking; confirm stale peers disappear and resources are released.
- [ ] Repeat the security checks with production-equivalent `.preSharedKey` provisioning: matching keys connect, mismatched keys do not, and no key material appears in logs, Bonjour metadata, or the app bundle.

If the product requires a specific topology (for example, a managed venue network or operation away from an access point), test that exact topology across the supported physical-device and OS matrix. A simulator-only pass is not a release gate.

## Internal event backpressure boundary

`Observable` now offers `updateBoundedAsync(_:)` as an **internal opt-in** path, with a positive capacity set at initialization (default 16). A caller waits asynchronously for a permit before its update enters the existing FIFO operation stream. Its Boolean result is `true` only after the update and observer callbacks finish; cancellation before stream enqueue or shutdown before admission returns `false`. A reserved permit is not yet an admitted update; once enqueued, cancellation does not retract it. `finish()` atomically closes bounded admission (including for a producer that reserved a permit but has not yet enqueued), wakes waiting producers with `false`, and closes the stream so its pump can drain already-enqueued operations; it **does not wait** for that drain. Use `await finishAndWait()` when shutdown must wait until all buffered operations and observer callbacks complete. `flush()` is a barrier only before the stream closes: after `finish()` it returns immediately because its barrier cannot be enqueued. Call `finish()` or `finishAndWait()` explicitly for shutdown: a suspended producer task may retain the `Observable`, so deinitialization alone cannot be relied on to wake it. Deinitialization closes the gate when the observable is actually released. The existing synchronous and async APIs are unchanged and never wait for these permits.

This is **not a global memory bound**: only opted-in, admitted updates consume the capacity budget. Legacy synchronous/async operations can still accumulate in the unbounded stream; callers can create arbitrarily many tasks waiting for a permit, retaining their payloads. FIFO means **execution order of already-admitted operations** in the shared stream, including legacy submissions. Concurrent waiting producers have no guaranteed admission order. No production manager/transport producer has been switched to the opt-in path, so it does not yet cap event volume for either backend.

## Connection policy defaults

Network connection lifecycle policy is intentionally fixed and internal while the backend remains opt-in:

| Policy | Current value | Why it is internal for now |
|---|---:|---|
| Handshake timeout | 10 seconds | Bounds unauthenticated/pre-registration connection lifetime without committing to public tuning semantics. |
| Maximum pending connections | 16 | Limits inbound/outbound handshakes before peer identity is validated. |
| Maximum connected peers | 8 | Keeps the experimental mesh small while local Network.framework behavior is still being validated. |
| Maximum discovered peers | 64 | Bounds the browser's endpoint table on busy or hostile Bonjour networks. Identities past the cap are ignored (no `.foundPeer`/`.lostPeer`) until a tracked peer is lost; already-tracked identities keep updating. |
| TCP keepalive | 30 s idle, 10 s interval, 3 probes | Detects silently vanished peers in roughly 60 seconds. The connection fails and follows the normal disconnect path, emitting `.devicesChanged`. |

There is deliberately no idle-connection timeout. A connected peer that sends nothing is normal for a mesh, and MultipeerConnectivity keeps such peers too. Keepalive probes close only connections whose remote end has stopped responding.

These defaults are covered by coordinator tests and may change before the Network backend becomes stable/default. Apps that need custom limits cannot tune them yet; they should validate whether the fixed policy fits their topology before shipping `.networkFramework` broadly, or keep using the default MultipeerConnectivity backend.

A future release can add public configuration once the project has enough device/CI evidence to know which knobs are necessary and how they should interact with peer discovery, reconnection, and browser UI.

## Current validation coverage

The Network backend currently has local loopback tests for:

- discovery/connect/message exchange
- bidirectional typed messages
- large typed payloads
- wrong-service isolation
- mismatched PSK rejection
- multi-peer broadcast
- disconnect/reconnect after peer restart

It also has mock-backed coordinator/unit tests for connection caps, duplicate connection handling, and handshake timeout behavior.

Run the focused Network tests with:

```sh
swift test --filter NetworkPeerLoopbackTests
```

In CI, the full Swift/Xcode test steps skip `NetworkPeerLoopbackTests` by default and then run them in focused retryable steps with `PEERCONNECTIVITY_RUN_NETWORK_E2E=1`. This keeps real Bonjour/Network.framework failures isolated from unit-test failures while still requiring the Network E2E checks to pass.

Full local automated verification for the migration stack (in addition to the physical-device checklist above):

```sh
swift test
xcodebuild test -project PeerConnectivity.xcodeproj \
  -scheme PeerConnectivity \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' \
  -configuration Debug
```

## Apple references

- [`NSLocalNetworkUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription) — Apple requires a purpose string for apps that access the local network directly or through Bonjour.
- [TN3151: Choosing the right networking API](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api) — Bonjour, local-network privacy, and peer-to-peer Wi-Fi guidance.
- [Local Network Privacy FAQ-14](https://developer.apple.com/forums/thread/663814) — Apple's mapping from a bare Multipeer Connectivity service type to `_service._tcp` in `NSBonjourServices`.
- [`NWListener.service`](https://developer.apple.com/documentation/network/nwlistener/service-swift.property) — the Bonjour service advertised by a Network listener.

## Known follow-ups

See [NetworkMigrationReadinessAudit.md](NetworkMigrationReadinessAudit.md) for the authoritative stable/default/removal gates and PR #50+ priority classification.

- Revisit public Network connection policy configuration after more device and CI validation.
- Reconsider a reusable Network-native browser component only after app-owned `PeerBrowserModel` integrations establish common UI requirements.
- Revisit stream or file transfer only as a separately scoped future feature; these APIs remain MultipeerConnectivity-only for the current Network backend.
- Implement an individually authenticated identity mode only after the design and gates in [NetworkTrustModelPlan.md](NetworkTrustModelPlan.md) receive focused security review.
- Continue monitoring Bonjour/Network.framework E2E behavior in CI and split or gate slow tests if they become flaky.
