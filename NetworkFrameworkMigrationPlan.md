# Network Framework Migration Plan

## Goal

Begin migrating PeerConnectivity away from direct MultipeerConnectivity dependence toward Apple's Network framework while preserving public API compatibility where practical.

> Note: the iOS 27 MultipeerConnectivity deprecation claim has not yet been verified against Apple SDK headers or release notes. Treat Network framework migration as proactive risk reduction until confirmed.

## Current State

PeerConnectivity currently wraps MultipeerConnectivity behind a mostly internal event pipeline:

```text
MC delegate -> EventProducer -> Observable -> PeerConnectionManager -> MultiObservable -> PeerConnectionResponder -> user listeners
```

Known MultipeerConnectivity dependency surface:

- `PeerConnectionManager.swift`
  - Main public API and orchestration.
  - Publicly exposes `multipeerSession: MCSession`, which is the largest compatibility constraint.
- `Peer.swift`
  - Stores internal `MCPeerID` identity.
- `PeerSession.swift`
  - Wraps `MCSession` data/resource/stream operations.
- `PeerSessionEventProducer.swift`
  - Implements `MCSessionDelegate` and translates session delegate callbacks into internal events.
- `PeerAdvertiser.swift`
  - Wraps `MCNearbyServiceAdvertiser`.
- `PeerAdvertiserEventProducer.swift`
  - Implements `MCNearbyServiceAdvertiserDelegate` and translates advertiser delegate callbacks into internal events.
- `PeerBrowser.swift`
  - Wraps `MCNearbyServiceBrowser`.
- `PeerBrowserEventProducer.swift`
  - Implements `MCNearbyServiceBrowserDelegate` and translates browser delegate callbacks into internal events.
- `PeerAdvertiserAssisstant.swift`
  - Wraps `MCAdvertiserAssistant`.
- `PeerAdvertiserAssisstantEventProducer.swift`
  - Implements `MCAdvertiserAssistantDelegate` and translates assistant delegate callbacks into internal events.
- `PeerConnectivityUI/PeerBrowserAssisstant.swift`
  - Uses `MCBrowserViewController`; Network framework has no equivalent built-in browser UI.
- `PeerConnectivityUI/PeerBrowserViewControllerEventProducer.swift`
  - Implements `MCBrowserViewControllerDelegate` for browser UI events.
- `PeerConnectivityUI/PeerConnectionManager+UI.swift`
  - Exposes browser UI using `multipeerSession` and `peerServiceType`.

Most public event types are already framework-neutral, which makes an incremental migration feasible.

## Network Framework Target Mapping

| MultipeerConnectivity | Network framework replacement | Notes |
|---|---|---|
| `MCNearbyServiceAdvertiser` | `NWListener` with Bonjour service | Advertise `_service._tcp` over Bonjour. |
| `MCNearbyServiceBrowser` | `NWBrowser` | Discover Bonjour endpoints. |
| `MCSession` | `NWConnection` set | Need connection manager for peer graph. |
| `MCSessionState` / `Peer.Status` | `NWConnection.State` mapping | Must define how `.setup`, `.waiting`, `.preparing`, `.ready`, `.failed`, and `.cancelled` map to existing public statuses/events. |
| `MCPeerID` | New framework-neutral peer identity | Must preserve display name and stable equality semantics. |
| `MCSession.send` | `NWConnection.send` + message framing | Network does not preserve message boundaries automatically. |
| Resource transfer | Custom protocol over `NWConnection` | Later slice; potentially file chunks/progress messages. |
| Stream transfer | Custom stream abstraction or compatibility shim | Later slice; no one-to-one replacement. |
| `MCBrowserViewController` | `PeerBrowserModel` + app-owned UI | Reusable PeerConnectivityUI replacement deferred pending app validation. |

Relevant Network framework APIs:

- `NWBrowser`
- `NWListener`
- `NWConnection`
- `NWParameters.includePeerToPeer = true`
- Bonjour service discovery/advertising
- `NWProtocolTLS.Options` for PSK/certificate identity
- Optional `NWProtocolFramer` for message framing

## Constraints and Risks

- Deployment target likely increases from iOS 8/macOS 10.10 to iOS 13/macOS 10.15 for Network framework APIs.
- iOS 14+ local network privacy requires app Info.plist entries:
  - `NSLocalNetworkUsageDescription`
  - `NSBonjourServices`
- Network framework is connection-oriented, not an `MCSession`-style symmetric mesh abstraction.
- Peer-to-peer Wi-Fi/Bluetooth/AWDL behavior requires `NWParameters.includePeerToPeer = true` and on-device testing.
- Network-backed transports must keep TLS enabled before any public backend selection is exposed; peer identities remain self-asserted until a later authentication/trust model binds them to TLS identity or app-provided verification.
- Network coordinator state must be serialized and bounded; current wiring keeps handshake timeout and connection caps internal until defaults are validated across CI and device testing. Discovery caps and idle timeouts remain production-hardening follow-ups before accepting untrusted inbound traffic at scale.
- Public `multipeerSession: MCSession` prevents completely removing MultipeerConnectivity without a breaking API change; a source-compatible transition release requires dual backend support.
- `MCBrowserViewController` has no Network framework equivalent.
- Need explicit message framing, handshake, peer identity exchange, reconnection, and duplicate-connection resolution.
- Existing `ServiceType` values are bare MultipeerConnectivity service names; Network Bonjour APIs require DNS-SD service names such as `_example._tcp`, so conversion or a documented breaking change is required.
- `Observable` and `MultiObservable` are not synchronized; Network framework callbacks on caller-provided queues may introduce races unless event delivery is serialized.
- `PeerConnectionType.custom` and `invitePeer(_:withContext:timeout:)` need explicit Network-backed semantics because MC invitations do not have a direct Network framework equivalent.

## Migration Strategy

Use a staged migration so each step can be reviewed, tested, and released independently.

### Phase 1 — Add testable transport seams

Objective: isolate current MultipeerConnectivity usage without changing behavior.

Tasks:

1. Introduce internal protocols for current session, session-event, advertising, advertiser-event, browsing, and browser-event responsibilities.
2. Make existing MC wrappers and event producers conform to those protocols.
3. Add internal factories/injection points to `PeerConnectionManager`.
4. Keep current public initializers and behavior unchanged.
5. Add mock-backed unit tests for `PeerConnectionManager` lifecycle, event forwarding, and send paths.

Recommended first implementation slice:

- Add internal operation protocols around `PeerSession`, `PeerBrowser`, and `PeerAdvertiser` rather than exposing `MCSession` directly to new code.
- Add internal event producer protocols where delegate callbacks enter the event pipeline.
- Update `PeerConnectionManager` to depend on injected factories for the current MC-backed wrappers.
- Add internal initializer/factory injection to enable mock sessions, browsers, and advertisers in tests.

Acceptance criteria:

- New mock-backed tests cover session lifecycle, send behavior, and event forwarding without creating real MultipeerConnectivity sessions.
- Existing tests continue to pass.
- Public API remains source-compatible.
- No Network framework implementation yet.

### Phase 2 — Define framework-neutral internal model

Objective: prepare internal types for either MC or Network backing.

Tasks:

1. Introduce internal peer identity abstraction decoupled from `MCPeerID`.
2. Define framework-neutral discovery, advertiser, session, and connection event protocols.
3. Keep `Peer` public behavior stable.
4. Add compatibility adapters from existing `MCPeerID`/MC events to neutral events.

Acceptance criteria:

- Event pipeline no longer requires MC-specific types outside MC adapter files.
- `PeerConnectionEvent` remains source-compatible.
- Tests cover peer identity equality and display-name behavior.

### Phase 3 — Build Network transport prototype

Objective: add Network framework implementation behind internal protocols.

Tasks:

1. Add `NetworkPeerBrowser` using `NWBrowser` Bonjour discovery.
2. Add `NetworkPeerListener` using `NWListener` Bonjour advertising.
3. Add `NetworkPeerConnection` using `NWConnection`.
4. Enable `includePeerToPeer` on listener, browser, and outbound connections.
5. Define how existing bare `ServiceType` strings map to Bonjour DNS-SD service names.
6. Define `.custom` mode and `invitePeer(_:withContext:timeout:)` behavior for Network-backed transports.
7. Add handshake message containing peer display name and stable peer identifier.
8. Implement duplicate connection resolution so two peers do not keep parallel connections indefinitely.
9. Add a message framing layer for data messages.

Acceptance criteria:

- Network implementation can discover and connect two local peers in an integration harness.
- Data send/receive works for JSON `PeerMessage` payloads.
- Connection state changes map to existing PeerConnectivity events.

### Phase 4 — Feature parity for data/resource/stream APIs

Objective: preserve current PeerConnectivity capabilities where possible.

Tasks:

1. Implement reliable data send parity.
2. Decide whether unreliable send can be supported or should become best-effort over TCP/TLS.
3. Implement resource transfer protocol with chunking and progress reporting.
4. Evaluate stream API compatibility and document limitations.
5. Add protocol-version negotiation for future compatibility.

Acceptance criteria:

- Existing public send APIs either work or have documented migration/deprecation path.
- Resource transfer has tests for success, failure, and progress callbacks.
- Any unsupported MC behavior is explicitly documented.

### Phase 5 — Public API migration and deprecations

Objective: guide consumers away from MC-specific API.

Tasks:

1. Add framework-neutral public accessors where needed.
2. Deprecate `multipeerSession: MCSession` if retaining it blocks Network-backed operation.
3. Add initializer/configuration to choose `.multipeerConnectivity` vs `.networkFramework` backend for a non-breaking transition release.
4. Decide whether already-deprecated `sendEvent(_:toPeers:)` and related legacy event observation APIs are removed in a major-version migration or retained through adapters.
5. Document deployment target changes and Info.plist requirements.
6. Update README examples.

Acceptance criteria:

- Consumers have a clear non-MC path.
- MC-specific public API is marked deprecated before removal.
- Migration guide explains breaking changes and fallback behavior.

### Phase 6 — App-owned browser UI foundation

Objective: support Network peer selection without prematurely standardizing reusable UI behavior.

Decision:

- Use the framework-neutral `PeerBrowserModel` as the supported replacement foundation for Network-backed apps.
- Keep rendering, selection, cancellation, progress, errors, accessibility, and presentation app-owned.
- Preserve the existing `MCBrowserViewController` path for the MultipeerConnectivity backend.
- Defer a reusable SwiftUI or UIKit browser until app integrations establish common requirements.

Acceptance criteria:

- Network-backed apps can observe discovered peers and connection status, then invite an app-approved peer through `PeerBrowserModel`.
- Documentation includes an app-owned UI example and clearly states that reusable browser UI is deferred.
- No default backend or MultipeerConnectivity browser behavior changes.

## Testing Plan

Start with unit tests, then add local integration tests.

Unit tests:

- Mock session transport send/disconnect behavior.
- Peer identity mapping.
- Message framing encode/decode.
- Handshake encode/decode.
- Duplicate connection resolution.

Integration tests/manual verification:

- Two simulators where supported.
- Two physical iOS devices on same Wi-Fi.
- Peer-to-peer/AWDL path with `includePeerToPeer = true`.
- Local network permission prompt behavior.
- macOS/iOS interoperability if supported.

Commands:

```bash
swift build
xcodebuild test -workspace PeerConnectivity.xcworkspace \
  -scheme PeerConnectivity \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug
```

## Documentation Updates

- README migration section.
- Info.plist requirements for Network/Bonjour/local network privacy.
- Deployment target changes.
- Backend selection/deprecation notes.
- Known limitations vs MultipeerConnectivity.

## Open Questions

1. Should Network framework be introduced as an opt-in backend first, or should it replace MC internally once stable?
2. What is the minimum supported OS after migration?
3. Is preserving `multipeerSession: MCSession` required for a transition release?
4. Should unreliable send semantics be preserved, deprecated, or documented as best-effort?
5. Is stream/resource transfer heavily used by consumers, or can those APIs be deprecated?
6. What service type naming convention should be required for Bonjour compatibility?
7. What authentication model should be default: no TLS identity, PSK, certificate identity, or app-provided verifier?
8. When should Network connection policy values become public configuration instead of fixed internal defaults?

## Immediate Next Step

Implement Phase 1's transport seam and mock-backed tests in this branch:

```text
feature/network-framework-migration
```

Keep this first commit behavior-preserving and small so later Network framework work can build on a stable abstraction layer.
