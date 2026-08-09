# Network Backend Guide

PeerConnectivity is migrating toward Apple's Network framework while preserving the existing MultipeerConnectivity-backed public API. The Network backend is available as an explicit opt-in migration path; the default backend remains `.multipeerConnectivity`.

## Release posture

The Network backend is not the default runtime path yet. Treat it as an experimental/beta backend for apps that can validate behavior in their own topology and OS/device matrix.

Use it when you need to evaluate the Network framework migration path for reliable local peer messaging. Continue using the default MultipeerConnectivity backend when you need browser UI, stream transfer, resource transfer, or proven production parity.

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

let secret = Data("replace-with-an-app-managed-secret".utf8)
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

`PeerConnectionNetworkSecurity.preSharedKey(_:)` configures TLS with a pre-shared key. Peers must use the same non-empty key to complete the TLS handshake.

Guidance for app-managed secrets:

- Use high-entropy key material, not a human-readable demo string.
- Store and rotate the secret according to your app's threat model.
- Use the same secret only for peers that should be allowed into the same local mesh.
- Treat Bonjour TXT metadata (`pc-id`, `pc-name`, `pc-v`) as routing/discovery metadata only. It is not a trust assertion.

`.unauthenticated` is plaintext TCP. It remains available only for migration compatibility and diagnostics and must not be used for sensitive data.

Current limitation: TLS-PSK authenticates membership in the shared-key group; it does not yet bind a long-term public peer identity to a certificate or pinned key. If multiple devices share the same PSK, any member of that group can advertise a display name. Apps that need stronger identity guarantees should keep the Network backend opt-in until a stricter trust model is added.

## Connection modes

### `.automatic`

Supported. Peers advertise and browse for the same service type, then attempt to connect automatically.

### `.custom`

Supported for app-owned peer selection. Use `PeerBrowserModel` to track discovered peers, render them in app UI, then call `invitePeer` for the selected peer:

```swift
let browserModel = PeerBrowserModel(manager: manager) { discoveredPeers in
    // Called on the main queue; render `discoveredPeers` in app UI.
}

browserModel.startObserving()

// Later, after user/app approval:
if let selectedPeer = browserModel.discoveredPeers.first {
    browserModel.invitePeer(selectedPeer)
}
```

For Network-backed managers, `invitePeer(_:withContext:timeout:)` uses the discovered peer endpoint. The `context` and `timeout` parameters are currently ignored.

### `.inviteOnly`

The built-in MultipeerConnectivity advertiser assistant/browser UI is not available for the Network backend. Network-backed apps should provide their own UI using `.foundPeer`, `.lostPeer`, and `invitePeer`.

`PeerConnectivityUI.browserViewController` returns `nil` for Network-backed managers.

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
| `sendDataStream` | ✅ | ❌ unsupported-operation error |
| `sendResourceAtURL` | ✅ | ❌ unsupported-operation error |
| Stream/resource receive events | ✅ | ❌ not implemented |
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

Resource transfer and stream APIs are intentionally unsupported for the Network backend in the current migration stack. Calls fail explicitly instead of silently degrading behavior.

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
- Evaluate a reusable Network-native browser component after app-owned `PeerBrowserModel` usage is validated.
- Decide whether to implement Network equivalents for streams and resource transfer or document them as MultipeerConnectivity-only long term.
- Strengthen identity binding beyond shared-key group membership for apps that require per-peer authentication.
- Continue monitoring Bonjour/Network.framework E2E behavior in CI and split or gate slow tests if they become flaky.
