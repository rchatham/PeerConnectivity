# Network Migration Readiness Audit

## Decision

As of the PR #49 stack base (`feature/network-migration-local-network-notes`), `.networkFramework` is a useful **experimental opt-in** for bounded local `Data` and `PeerMessage` evaluation. It is **not ready to be described as stable, made the default, or used to remove MultipeerConnectivity**.

No runtime merge blocker was found for the current opt-in stack. The remaining gates below belong to later, separately reviewed PRs; this audit does not authorize a backend-default change.

This document is the authoritative readiness checklist. The earlier [migration plan](NetworkFrameworkMigrationPlan.md) records the staged architecture, the [PR plan](NetworkMigrationPRPlan.md) records how the stack was decomposed, the [backend guide](NetworkBackendGuide.md) describes current adopter behavior, and the [trust plan](NetworkTrustModelPlan.md) defines the security boundary.

## Readiness levels

These decisions are separate:

1. **Experimental opt-in (current):** adopters explicitly select `.networkFramework` and accept documented limitations.
2. **Stable opt-in:** the project supports the Network backend as a production API for its documented capability set, but does not select it implicitly.
3. **Default:** existing initializer call sites select Network unless they explicitly request MultipeerConnectivity.
4. **MultipeerConnectivity removal:** MC implementation and public compatibility surfaces are deleted in a breaking release.

A later level inherits every gate from the preceding levels. “Parity” means parity for the declared reliable-message product, not implementation of every MC feature.

## Completed capabilities

Verified against `Sources`, `PeerConnectivityTests`, and the current stacked documentation:

- [x] The package and podspec support iOS 13+ and macOS 10.15+; the iOS-only Xcode project targets iOS 13+.
- [x] Transport seams and framework-neutral `PeerIdentity` allow `PeerConnectionManager` to construct either backend.
- [x] `.multipeerConnectivity` remains the initializer default; `.networkFramework` is explicit opt-in and availability-checked.
- [x] Network Bonjour advertising/discovery maps bare service names such as `local` to `_local._tcp` and publishes bounded versioned identity metadata.
- [x] `.automatic` discovery/connection and `.custom` app-owned selection are wired. `PeerBrowserModel` provides a main-queue model for app-owned UI.
- [x] TCP message framing handles partial/coalesced input, rejects unknown/oversized frames, and caps a payload at 1 MiB.
- [x] Reliable `Data` and typed `PeerMessage` exchange, targeted sends, broadcasts, duplicate-connection resolution, disconnect, and reconnect paths are implemented.
- [x] Coordinator state is serialized and currently bounds handshakes to 10 seconds, pending connections to 16, and connected peers to 8.
- [x] `.preSharedKey` enables external-PSK transport pinned to TLS 1.2 as both the minimum and maximum, with no fallback to another TLS version or plaintext; `.unauthenticated` is explicitly documented as a separate plaintext diagnostics/migration compatibility mode.
- [x] Observable/listener mutation is synchronized and concurrency tests cover registration, removal, and delivery.
- [x] Unit tests cover protocol parsing, state mapping, duplicate handling, caps, timeout behavior, transport adapters, manager routing, and browser-model behavior.
- [x] Opt-in loopback coverage exercises discovery, service isolation, bidirectional/large typed messages, multi-peer broadcast, PSK mismatch, and reconnect. CI isolates and retries these real Network/Bonjour tests.
- [x] Adopter documentation covers backend selection, local-network privacy metadata, service mapping, device/network caveats, PSK handling, demo usage, and manual physical-device validation.

## Known non-parity and accepted boundaries

| Area | Current Network behavior | Readiness effect |
|---|---|---|
| Streams/resources | `sendDataStream` throws; resource sends return `nil` and complete with an error; receive events are not emitted. | Accepted for stable reliable-message scope. Before MC removal, either replace these APIs or remove them in a documented breaking release. |
| Browser UI | No `MCBrowserViewController` or advertiser-assistant equivalent; apps use `PeerBrowserModel` and app-owned UI. | Accepted. A reusable Network UI is optional, not a stable/default/removal gate. |
| Invitation semantics | Network `invitePeer` ignores `context` and its caller-supplied `timeout`; `.inviteOnly` has no MC invitation dialog/handler equivalent, and inbound Network connections are transport-accepted subject to protocol/security checks. | Must be made explicit in the stable API contract. Implement equivalent approval semantics only if supported products require them. |
| Public MC session | `multipeerSession` remains public and traps when used with Network. | Tolerable only during dual-backend transition; deprecate and replace before MC removal. |
| Security certificate event | `.receivedCertificate` reflects MC delegate behavior and has no Network equivalent. | Document as MC-only before stable; deprecate/remove or replace before MC removal. |
| Discovery/start failures | MC startup failures become `.error`; current Network listener/browser state failures are not forwarded through that public path. | Blocking for stable: permission, listener, browser, and connection failures need an observable, tested contract. |
| Send outcomes | Public `sendData`/`sendMessage` do not report asynchronous send failure on either backend; Network send completions are currently discarded. | Define and test the stable support contract. Add an outcome API if production requirements cannot tolerate best-effort caller visibility. |
| Identity | Bonjour and handshake identifiers/display names are self-asserted. A group PSK authenticates only possession of the shared group key. | Blocking for stable/default. Do not authorize or audit by `Peer` identity today. |
| Policy | Handshake and connection caps are fixed/internal; there is no idle timeout or discovery cap. | Validate defaults and add missing resource bounds before stable use on untrusted/local hostile networks. Public tuning is required only if validated products need it. |
| Device evidence | Automated Network tests are local loopback/simulator-oriented; the documented physical-device matrix has not been completed by this stack. | Blocking for stable/default. |

## Gate: stable opt-in

Do not remove the “experimental/beta” label until every item is complete:

### Security and protocol

- [ ] Select and implement one individually authenticated trust mode from `NetworkTrustModelPlan.md`.
- [ ] Bind authenticated principal, stable transport identifier, and mutable display name before registration, connected/data events, or duplicate resolution.
- [ ] Fail closed and add spoofing, identity-mismatch, replay, stale/revoked credential, downgrade, timeout, cancellation, and verifier-error tests.
- [ ] Complete focused security and privacy review with no unresolved high-severity findings.
- [ ] Version the handshake/trust negotiation and document compatibility and downgrade behavior.

### Reliability and operations

- [ ] Forward Network browser, listener, permission-related, and connection failures through a documented public error/state contract.
- [ ] Add discovery bounds and idle-connection lifecycle policy, or document evidence that an alternate bound closes those resource-exhaustion paths.
- [ ] Validate the 10-second/16-pending/8-connected defaults under expected load, churn, backgrounding, and hostile discovery. Expose configuration only where evidence establishes a consumer need.
- [ ] Decide whether reliable-message send completion/failure needs public API; test whichever contract is selected.
- [ ] Run soak/churn tests for repeated start/stop, background/foreground, peer loss, duplicate races, malformed traffic, and capacity recovery.

### Product and validation

- [ ] Freeze the supported capability matrix, including invitation/context/timeout behavior and MC-only events.
- [ ] Complete the `NetworkBackendGuide.md` physical-device checklist on the release build across the supported iOS/macOS versions, device classes, infrastructure Wi-Fi, required peer-to-peer topology, Local Network allow/deny/recovery, and production-equivalent key provisioning.
- [ ] Record results and establish a repeatable release regression matrix; simulator/loopback success alone is insufficient.
- [ ] Validate at least one real adopting app using app-owned discovery UI, lifecycle handling, and production topology.
- [ ] Publish troubleshooting and compatibility guidance for blocked Bonjour, VPN/firewall/managed-network policy, and permission denial.

## Gate: default backend

In addition to all stable-opt-in gates:

- [ ] Collect at least one stable release cycle of opt-in production/device evidence with no unresolved critical regressions.
- [ ] Define a secure default initialization story. The current default `networkSecurity: .unauthenticated` cannot accompany an implicit Network backend switch.
- [ ] Decide how existing source-compatible initializer calls obtain/provision trust material, or require an explicitly breaking initializer migration.
- [ ] Publish a migration guide for changed discovery, `.inviteOnly`, browser UI, stream/resource, certificate, identity, error, and networking behavior.
- [ ] Audit all examples and demo paths so no default path silently uses plaintext transport.
- [ ] Treat the switch as a breaking behavioral release, with an explicit `.multipeerConnectivity` rollback option for at least one transition release.
- [ ] Verify release telemetry/support ownership and rollback criteria before changing the factory default.

## Gate: MultipeerConnectivity removal

In addition to the default-backend gates:

- [ ] Deprecate `multipeerSession` and all other MC-specific public behavior in a released transition version, with framework-neutral replacements where retained behavior needs them.
- [ ] Resolve stream/resource APIs and receive events: implement a separately versioned Network protocol or remove them with major-version migration notes. They are not required to make Network stable/default, but unresolved APIs block MC removal.
- [ ] Resolve `MCBrowserViewController`, advertiser-assistant, certificate-event, invitation-context, and invitation-handler compatibility. A reusable browser is not mandatory if app-owned UI is the declared replacement.
- [ ] Decide the fate of legacy `sendEvent`/event-observation APIs independently of transport removal; do not conflate existing deprecation with Network parity.
- [ ] Remove MC adapters, imports, `MCPeerID` storage/bridges, `MCSession` exposure, UI product dependencies, and podspec framework linkage; prove the core and UI products build without `MultipeerConnectivity.framework`.
- [ ] Add source/API migration tests or fixtures for the supported replacement surface and verify no shipped target links MC.
- [ ] Publish the removal only in a breaking major release after the announced deprecation window.

## Optional PR #50+ disposition

No optional implementation is required to merge this documentation audit or the experimental opt-in stack.

| Follow-up | When required |
|---|---|
| Individual peer authentication and negative security suite | **Before stable**, therefore also before default/removal. |
| Network error/permission observability | **Before stable**. |
| Discovery cap, idle lifecycle bound, soak/churn/device matrix | **Before stable**. |
| Public policy configuration | **Later only if validation shows adopters need tuning**; fixed validated defaults are acceptable. |
| Public send-result API | **Later if the frozen production contract requires caller-visible delivery failure**; the decision itself is required before stable. |
| Reusable SwiftUI/UIKit Network browser | **Optional**; not required for stable, default, or removal if app-owned UI remains the product decision. |
| Network stream/resource protocol | **Optional before stable/default**; required before removal only if those APIs are retained. A major-release API removal is the alternative. |
| Invitation context/timeout or inbound approval parity | **Product-dependent**; freeze/document before stable, implement before default/removal only if the supported contract promises it. |
| Default backend switch | **Only after stable gates and transition evidence**; not part of the current stack. |
| MC adapter/API deletion | **Only after deprecation and breaking-release gates**. |

## Release and versioning notes

- Release the current stack as an opt-in experimental/beta feature, not as production parity. Keep `.multipeerConnectivity` as the default.
- Call out the already-applied minimum-platform increase to iOS 13/macOS 10.15 in release notes. CocoaPods remains legacy and does not carry `PeerConnectivityUI`; SwiftPM is the primary distribution path.
- Treat protocol/trust negotiation as versioned wire behavior. Do not silently reinterpret protocol version 1 peers when individual identity is introduced.
- A stable opt-in can ship in a feature release if its API remains additive and the experimental contract reserved change; document the security and behavior transition prominently.
- Changing the default is behaviorally breaking even if source-compatible. Removing MC types/APIs or stream/resource behavior is source/ABI breaking and requires a major release plus a deprecation window.
- Update `CHANGELOG.md`, README support tables, package/podspec metadata, generated API docs, and adopting-app plist guidance in each release PR; do not add unreleased promises to the historical changelog now.

## Risk register

| Risk | Severity now | Current control | Closure gate |
|---|---|---|---|
| Group member spoofs identifier/display name | Critical for identity-based authorization | Experimental label, PSK boundary documentation | Individual identity binding and adversarial security tests before stable |
| Default initializer would select plaintext Network transport | Critical if default switched | MC remains default | Secure initialization/provisioning design before default |
| Local Network denial or listener/browser failure is not surfaced consistently | High | Manual guide; MC error event path exists | Public Network error/state propagation before stable |
| Unbounded discovery and no idle timeout enable resource pressure | High on hostile local networks | 16 pending / 8 connected / 10-second handshake bounds | Add/justify bounds and load testing before stable |
| Device/AWDL/topology behavior differs from loopback/simulator | High | `includePeerToPeer`, isolated E2E CI, manual checklist | Recorded physical-device regression matrix before stable |
| MC-only stream/resource consumers break on switch/removal | High | Explicit unsupported errors and MC default | Migration plan before default; replacement or breaking removal before MC deletion |
| `.inviteOnly` implies approval semantics Network does not provide | High for approval-dependent apps | App-owned UI guidance | Freeze contract and validate adopting app before stable/default |
| Asynchronous send failures are invisible to callers | Medium–high | TCP/TLS and connection-state cleanup | Decide/test contract before stable; add API if required |
| Internal policy defaults do not fit larger meshes | Medium | Conservative fixed caps and unit tests | Device/load evidence; public configuration only if needed |
| Bonjour, VPN, firewall, guest/managed network, or permission policy blocks operation | Medium | Production setup and troubleshooting caveats | Device/topology validation and actionable errors before stable |
| Protocol evolution strands or downgrades peers | Medium–high | Handshake version rejects unsupported versions | Versioned trust negotiation and interoperability tests before stable |
| Removing MC breaks public `MCSession`, UI, certificate, and transfer surfaces | High | Dual backends retained | Deprecation window and major release before removal |

## Audit evidence

Claims in this checklist were reconciled against:

- `Sources/PeerConnectionManager.swift`, `PeerConnectionTransports.swift`, `NetworkPeerTransport.swift`, `NetworkPeerTransportAdapters.swift`, `NetworkPeerCoordinator.swift`, `PeerNetworkProtocol.swift`, `PeerBrowserModel.swift`, and `PeerConnectionResponder.swift`;
- the complete `PeerConnectivityTests` suite and `.github/workflows/ci.yml` test split;
- `Package.swift`, `PeerConnectivity.podspec`, and the Xcode project deployment settings; and
- `NetworkFrameworkMigrationPlan.md`, `NetworkMigrationPRPlan.md`, `NetworkBackendGuide.md`, and `NetworkTrustModelPlan.md`.

The automated test commands verify the current implementation; they do not satisfy the unchecked physical-device, security-design, production-adoption, or release-transition gates above.
