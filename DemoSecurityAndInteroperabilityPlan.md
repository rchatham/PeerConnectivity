# Demo Security and Backend Interoperability Plan

## Purpose

Define the implementation needed to expose existing transport security in the demo and clarify whether MultipeerConnectivity and Network.framework peers can communicate with each other.

## Executive summary

- Security exists in both backends, but the demo currently hardcodes their least-disruptive defaults and exposes no security controls.
- The Network backend already supports TLS with a pre-shared key (PSK). The current demo always selects plaintext `.unauthenticated` transport.
- The MultipeerConnectivity backend already supports encryption preference, security identity, certificate policy, and invitation policy. The current demo uses optional encryption, no identity, and accepts certificates/invitations by default.
- The two backends are not wire-compatible and cannot directly discover, invite, authenticate, or exchange framed messages with each other.
- This work adds demo security controls for both backends without changing public library APIs.
- Interoperability remains report-only. No bridge, gateway, adapter, or common-wire-protocol code is in scope.

## Current implementation

### MultipeerConnectivity security

Public configuration is defined in `Sources/PeerSecurityConfiguration.swift` and passed through `PeerConnectionManager`.

| Capability | Existing API | Current demo value |
|---|---|---|
| Session encryption | `PeerSecurityConfiguration.encryptionPreference` | `.optional` through `.default` |
| Required encryption preset | `PeerSecurityConfiguration.encrypted` | Not exposed |
| Local certificate identity | `securityIdentity` | `nil` |
| Remote certificate policy | `PeerCertificatePolicy` | `.acceptAll` |
| Invitation policy | `PeerInvitationPolicy` | `.acceptAll` |

`PeerSecurityConfiguration.encrypted` requires transport encryption, but it does not by itself provide a local certificate identity or authenticated peer identity.

### Network.framework security

`PeerConnectionNetworkSecurity` is defined in `Sources/PeerConnectionManager.swift`:

- `.unauthenticated`: plain TCP; this is the current default and the value hardcoded by the demo.
- `.preSharedKey(Data)`: TLS-PSK configured in `Sources/NetworkPeerTransport.swift`.

The Network PSK implementation is end-to-end and already covered by loopback tests, including mismatched-key rejection. Its trust boundary is limited:

- A sufficiently random shared key authenticates membership in a group.
- It does not authenticate an individual peer.
- Bonjour TXT metadata and handshake names/identifiers remain self-asserted.
- Any group-key holder can impersonate another member's display name or identifier.

See `NetworkTrustModelPlan.md` for the complete threat model.

### Current demo behavior

`PeerConnectivityDemo/ViewController.swift` currently creates the manager with:

```swift
securityConfiguration: .default
invitationPolicy: .acceptAll
networkSecurity: .unauthenticated
```

The demo labels the Network path as unauthenticated, but users cannot select the implemented PSK path or require Multipeer encryption.

## Proposed demo security UI

Add a **Security** section beneath Backend and Connection Behavior. Security selection is backend-specific, remembered per backend during the demo session, and disabled while networking runs.

### Multipeer options

1. **Compatible (Optional Encryption)** — existing `.default` behavior.
2. **Require Encryption** — use `.encrypted`.

Initial scope should not expose certificate identity or custom certificate callbacks. Those require credential provisioning, certificate inspection, and a more deliberate trust UX than a demo toggle.

Display copy:

- Compatible: `Optional session encryption · nil identity and accept-all certificates do not authenticate peers`
- Require Encryption: `Required session encryption · peers remain unauthenticated and MITM-vulnerable with nil identity and accept-all certificates`

Required Multipeer encryption protects transport confidentiality but does not authenticate peers in this demo. Its nil local identity and accept-all remote certificate policy leave the session vulnerable to man-in-the-middle attacks.

### Network options

1. **Unauthenticated** — existing plaintext demo path.
2. **TLS with Shared Key** — use `.preSharedKey(Data)`.

When TLS with Shared Key is selected, show a secure text field accepting a Base64-encoded key.

Validation requirements:

- Decode Base64 explicitly; reject malformed input.
- Require at least 32 decoded bytes for the demo, even though the library currently only requires a non-empty key.
- Do not silently fall back to unauthenticated transport after validation failure.
- Both peers must use identical key bytes.
- Disable editing while networking runs.
- Clear the key on **Reset Demo**, which drops the demo's references without claiming secure memory erasure.
- Preserve the selected mode and in-memory key across ordinary **Stop** so a session can restart.
- Never persist, log, export, include in status/accessibility text, copy into screenshots, or place the key in Bonjour metadata.
- Harden the field against autocorrection, spell checking, smart substitutions, and password autofill.

Display copy:

- Unauthenticated: `Plain TCP · non-sensitive local testing only`
- TLS-PSK: `TLS shared-key group authentication · not individual peer identity`

### Key generation

Provide a **Generate Test Key** button that creates 32 random bytes with `SecRandomCopyBytes`, stores them only in memory, and shows the Base64 value in the secure field.

For two-instance simulator testing, support a launch argument such as:

```text
PCNetworkPSKBase64 <base64-value>
```

`PCNetworkPSKBase64` is compiled and read only under `#if DEBUG` and passes through the same strict validation as manual input. It is for local validation only: process arguments can be inspected by other tooling and are not appropriate production secret storage. Manual identical input or this debug argument is the transfer mechanism; the demo does not add key copying.

`SecRandomCopyBytes` failure must produce no key and an actionable inline error. Keep generation injectable/testable where practical and cover both successful 32-byte output shape and injected failure.

### Interaction with Connection Behavior

Security and connection behavior are independent:

- Automatic + Multipeer encryption
- Require Invitation + Multipeer encryption
- Automatic + Network TLS-PSK
- Require Invitation + Network TLS-PSK

`PeerInvitationPolicy` should remain separate from the demo's connection behavior selector. Manual connection mode already provides explicit app-owned invitations for both backends.

## Implementation tasks

### PR A — Demo security controls

Suggested branch/base:

```text
feature/network-migration-demo-security
  -> feature/network-migration-demo-network-mode
```

Files:

- `PeerConnectivityDemo/ViewController.swift`
- `PeerConnectivityDemo/README.md`
- `NetworkBackendGuide.md`
- `README.md`
- `Artifacts/peer-browser-network-demo.png`
- `docs/images/better-demo-app-home.png`

Tasks:

1. Add backend-specific demo security enums/state.
2. Add security segmented control or menu and Network PSK field/generator.
3. Map Multipeer selection to `.default` or `.encrypted`.
4. Map Network selection to `.unauthenticated` or `.preSharedKey(decodedKey)`.
5. Validate before manager construction and present an actionable inline error.
6. Keep controls disabled while networking runs.
7. Keep the selected security/key across ordinary Stop; clear it on Reset by dropping references without claiming secure erasure.
8. Keep `invitationPolicy: .acceptAll`; verify Automatic and Require Invitation remain independent from security selection.
9. Update status, troubleshooting, accessibility labels, logs, and docs without exposing key bytes.
10. Refresh both Multipeer and Network screenshots with the key field empty or redacted; real keys must not appear.
11. Do not implement any interoperability bridge code.

### Tests

Existing library tests already verify core security behavior. Add only focused gaps:

- Add an internal pure Base64/length validation helper under `Sources` without changing public API. Cover empty, malformed, strict whitespace rejection, 31-byte rejection, 32-byte acceptance, and fail-closed configuration mapping.
- Invalid TLS input must never map or fall back to `.unauthenticated` and must be blocked before the existing Network transport non-empty-key precondition.
- Cover generated-key success shape and injected random-generation failure where practical.
- Keep existing Network matching-PSK connection/message tests.
- Keep existing mismatched-PSK rejection tests.
- Keep existing Multipeer security-configuration mapping tests.

Manual simulator verification:

1. Network + same 32-byte PSK: connect and exchange typed messages.
2. Network + mismatched PSKs: no connected peer; show/log a useful failure without key material.
3. Network + malformed/short key: Start is blocked locally.
4. Multipeer + Require Encryption: connect and exchange typed messages.
5. Each security mode combined with Automatic and Require Invitation.
6. Reset clears the Network key.

Required commands:

```bash
swift test
xcodebuild test -project PeerConnectivity.xcodeproj \
  -scheme PeerConnectivity \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' \
  -configuration Debug
xcodebuild -project PeerConnectivityDemo.xcodeproj \
  -scheme PeerConnectivityDemo \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Security review is required before push.

## Backend interoperability assessment (report only)

This section documents the current boundary. It does not authorize implementation of bridge code in this work.

### Direct interoperability

Direct MultipeerConnectivity-to-Network.framework interoperability is not possible with the current backends.

| Layer | MultipeerConnectivity | Network.framework | Incompatibility |
|---|---|---|---|
| Discovery | `MCNearbyServiceBrowser` / advertiser | Bonjour `NWBrowser` / `NWListener` | Separate discovery planes |
| Transport | Private `MCSession` transport | TCP | Different wire transport |
| Framing | Apple-managed/opaque | Custom kind + length framing | No shared decoder |
| Handshake | MC invitation/session setup | `PeerNetworkHandshake` frame | Different state machines |
| Invitations | MC invitation callback | Direct Network connection | No common invitation exchange |
| Identity | Archived `MCPeerID` | UUID-backed `PeerIdentity` | No shared identity representation |
| Security | MC encryption/certificates | Plain TCP or TLS-PSK | No common negotiation or credentials |

A Multipeer peer cannot simply connect to `_local._tcp`, and a Network peer cannot join an `MCSession`.

### Possible approaches

#### 1. Require both apps to select the same backend — recommended

This is the migration model already implemented. It is simple, testable, and avoids pretending the protocols interoperate.

#### 2. Dual-stack app with app-level bridging

One process could run one manager for each backend and relay application messages between them. This is a gateway, not direct interoperability.

Required design work:

- Run two simultaneous managers without peer/event collisions.
- Define bridge routing, loop prevention, deduplication, and delivery semantics.
- Map unrelated peer identities safely.
- Define whether bridged peers are visible and how trust is represented.
- Prevent a weak/unauthenticated side from silently downgrading a secure side.
- Decide whether invitations and connection state are bridged or only messages.
- Add multi-process/device end-to-end tests.

Security risk: a bridge terminates both security domains and becomes a trusted message relay. End-to-end identity and confidentiality do not carry across it automatically.

#### 3. Common public wire protocol

Replacing both transports with a shared protocol would require reimplementing the Multipeer side rather than using `MCSession` as-is. Apple's Multipeer wire protocol is opaque, so this is effectively a new transport, not an adapter.

### Recommendation

Do not combine interoperability work with demo security controls.

- Implement demo controls for the security capabilities that already exist.
- Continue requiring peers to select the same backend.
- If mixed-fleet communication is a real product requirement, create a separate architecture decision record for a dual-stack gateway and define its threat model before implementation.

## Readiness and sequencing

1. **Now:** demo security controls using existing APIs.
2. **Before calling Network stable:** individual peer authentication and production provisioning, as required by `NetworkMigrationReadinessAudit.md`. TLS-PSK in this demo authenticates group membership only, never individual identity.
3. **Only if product-required:** dual-stack gateway design and prototype.
4. **Do not claim backend interoperability** unless a separately tested bridge is shipped and its security boundary is documented.
