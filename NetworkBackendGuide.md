# Network Backend Guide

PeerConnectivity is migrating toward Apple's Network framework while preserving the existing MultipeerConnectivity-backed public API. The Network backend is available as an explicit opt-in migration path; the default backend remains `.multipeerConnectivity`.

## Release posture

The Network backend is not the default runtime path yet. Treat it as an experimental/beta backend for apps that can validate behavior in their own topology and OS/device matrix.

Use it when you need to evaluate the Network framework migration path for reliable local peer messaging. Continue using the default MultipeerConnectivity backend when you need the system-provided browser UI, stream transfer, resource transfer, stream/resource receive events, or proven production parity.

## Requirements

- `.networkFramework` requires iOS 13.0+ or macOS 10.15+.
- iOS apps that use Bonjour/local-network discovery should include local network privacy entries in `Info.plist`:
  - `NSLocalNetworkUsageDescription`
  - `NSBonjourServices`, including the DNS-SD form of your service type, for example `_local._tcp`.
- Service types passed to `PeerConnectionManager` remain bare PeerConnectivity service names such as `"local"`; the Network backend maps them to Bonjour service names internally.

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

`PeerConnectionNetworkSecurity.preSharedKey(_:)` configures TLS with a pre-shared key. Peers must use the same non-empty key to complete the TLS handshake. This authenticates each endpoint only as a member of the key-sharing group, not as a particular person, device, account, or installation.

Guidance for app-managed secrets:

- Generate at least 256 random bits (32 bytes) with a cryptographically secure random-number generator. Do not use a password, passphrase, display name, service name, UUID text, predictable token, or demo string.
- Provision the key over an authenticated channel; keep it out of source, logs, Bonjour metadata, and the application bundle; store it with platform-appropriate protection.
- Scope the key to one app/environment and authorization group. Do not reuse it across unrelated protocols or groups.
- Rotate the key when membership changes or compromise is suspected.
- Treat every holder of the shared key as equally authorized under this mode.
- Treat Bonjour TXT metadata (`pc-id`, `pc-name`, `pc-v`) as routing/discovery metadata only. It is not a trust assertion.

`.unauthenticated` is plaintext TCP. It remains available only for migration compatibility and diagnostics and must not be used for sensitive data.

Current limitation: TLS-PSK authenticates membership in the shared-key group; it does not bind the self-asserted handshake identifier or display name to an individual credential. Any member can claim another member's display name or identifier, so apps must not use `Peer.displayName` or the internal transport identifier as an authorization principal or trustworthy audit identity. Apps that need stronger identity guarantees should keep the Network backend opt-in until a stricter trust model is added.

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

For Network-backed managers, `invitePeer(_:withContext:timeout:)` uses the discovered peer endpoint. The `context` and `timeout` parameters are currently ignored.

### `.inviteOnly`

The built-in MultipeerConnectivity advertiser assistant/browser UI is not available for the Network backend. Network-backed apps should provide their own UI using `.foundPeer`, `.lostPeer`, and `invitePeer`.

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
| TLS-PSK transport security | MC-managed | ✅ with `.preSharedKey` |

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

## Stream and resource compatibility decision

`sendDataStream`, `sendResourceAtURL`, `.receivedStream`, `.startedReceivingResource`, and `.finishedReceivingResource` remain MultipeerConnectivity-only APIs for the current Network backend. They are not deprecated because they remain supported when using `.multipeerConnectivity`, but selecting `.networkFramework` does not provide alternate stream or resource semantics.

This migration stack will not add a custom stream or file-transfer protocol. Network framework has no direct equivalents for the MultipeerConnectivity APIs, and emulating them would require new framing, flow-control, progress, cancellation, persistence, and protocol-versioning contracts beyond the reliable `Data` and `PeerMessage` transport being migrated.

Network-backed `sendDataStream` calls throw an unsupported-operation error. Network-backed `sendResourceAtURL` calls return `nil` progress for each requested peer and invoke the completion handler with an unsupported-operation error. The Network backend never emits the stream or resource receive events. Calls fail explicitly rather than silently changing transport behavior.

Apps that need to exchange bounded in-memory payloads should use `sendData` or `sendMessage`. Apps that require stream or resource transfer must keep those sessions on `.multipeerConnectivity`. A future, separately scoped feature may revisit file or streaming transport, but it is not a parity requirement for the current Network migration.

## Demo app

The demo shows the active backend and lets you choose **Multipeer** or **Network** before starting. The default remains MultipeerConnectivity. In Network mode, the manager uses `.custom`, discovered rows come from `PeerBrowserModel`, and the **Invite selected peer** and **Send typed ping** actions exercise manual invitation and `PeerMessage` delivery.

The same path can be selected with launch arguments:

- `PCNetworkBackend` — select `.networkFramework` instead of the default MultipeerConnectivity backend.
- `PCAutoStart` — start the manager on launch.
- `PCDisplayName <name>` — set a deterministic display name such as `Alice` or `Bob`.

Example arguments for two simulator or device instances:

```text
PCNetworkBackend PCAutoStart PCDisplayName Alice
PCNetworkBackend PCAutoStart PCDisplayName Bob
```

Select a discovered peer, invite it, wait for its status to become **Connected**, then send a typed ping. See [`PeerConnectivityDemo/README.md`](PeerConnectivityDemo/README.md) for the complete walkthrough.

This demo Network path is intentionally unauthenticated, visibly labels that limitation, and is only for non-sensitive local migration validation. Production apps should use app-managed `.preSharedKey` material and an appropriate trust model.

## Connection policy defaults

Network connection lifecycle policy is intentionally fixed and internal while the backend remains opt-in:

| Policy | Current value | Why it is internal for now |
|---|---:|---|
| Handshake timeout | 10 seconds | Bounds unauthenticated/pre-registration connection lifetime without committing to public tuning semantics. |
| Maximum pending connections | 16 | Limits inbound/outbound handshakes before peer identity is validated. |
| Maximum connected peers | 8 | Keeps the experimental mesh small while local Network.framework behavior is still being validated. |

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

Full local verification for the migration stack:

```sh
swift test
xcodebuild test -project PeerConnectivity.xcodeproj \
  -scheme PeerConnectivity \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' \
  -configuration Debug
```

## Known follow-ups

- Revisit public Network connection policy configuration after more device and CI validation.
- Reconsider a reusable Network-native browser component only after app-owned `PeerBrowserModel` integrations establish common UI requirements.
- Revisit stream or file transfer only as a separately scoped future feature; these APIs remain MultipeerConnectivity-only for the current Network backend.
- Implement an individually authenticated identity mode only after the design and gates in [NetworkTrustModelPlan.md](NetworkTrustModelPlan.md) receive focused security review.
- Continue monitoring Bonjour/Network.framework E2E behavior in CI and split or gate slow tests if they become flaky.
