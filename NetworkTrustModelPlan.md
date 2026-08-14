# Network Backend Trust Model Plan

## Status and scope

This document defines the security boundary of the experimental Network framework backend and the requirements for strengthening it. It is a plan, not a production authentication implementation. It does not change the default `.multipeerConnectivity` backend, add a transport, or define a public trust-policy API.

## Current security boundary

The Network backend has two modes:

- `.unauthenticated` is plaintext TCP and provides neither confidentiality nor peer authentication.
- `.preSharedKey` passes one app-provided key and the fixed PSK identity label `PeerConnectivity.NetworkFramework.PSK.v1` to `sec_protocol_options_add_pre_shared_key` on both listener and outbound connections. Apple's external PSK API supports PSK negotiation only in TLS 1.2, so the transport sets both its minimum and maximum protocol versions to TLS 1.2. Negotiation cannot fall back to another TLS version or to plaintext.

Apple's Security framework describes the external-PSK inputs as the PSK and its PSK identity. A PSK identity is a **label for a key**, not the authenticated identity of the endpoint using that key. The fixed PeerConnectivity label therefore selects the protocol's shared key; it does not identify Alice, Bob, a device, or an installation.

A successful current TLS-PSK connection establishes only that the remote endpoint knows the same group secret. It provides encrypted, integrity-protected transport against parties outside that group. It does **not** establish which individual group member is connected.

The following values remain self-asserted:

- Bonjour TXT `pc-id` and `pc-name`, which are visible before connection and used for discovery/routing.
- `PeerNetworkHandshake.identity.identifier` and `.displayName`, which are sent after transport setup but are not cryptographically bound to an individual key.
- Public `Peer.displayName`, which reflects the handshake identity after connection.

TLS protection prevents a non-member from modifying a connected member's handshake in transit, but every holder of the group PSK can create its own valid TLS connection and assert any identifier or display name.

## PSK requirements

Apps using `.preSharedKey` should meet all of these requirements:

1. **Generate at least 256 random bits (32 bytes)** with a cryptographically secure random-number generator. This is a conservative project requirement above TLS's baseline security level.
2. Do not use passwords, passphrases, display names, service names, UUID text, predictable tokens, or demo strings directly as PSKs. Low-entropy external PSKs can permit offline dictionary attacks against an observed handshake; pinning this transport to TLS 1.2 does not make password-like key material safe.
3. Provision the key over an authenticated channel and store it using platform-appropriate protected storage. Do not embed a production group key in source, examples, logs, Bonjour metadata, or the application bundle.
4. Scope a key to one app/environment and one intended authorization group. Do not reuse it across unrelated protocols, production and test environments, or groups with different privileges.
5. Rotate the key when membership changes or compromise is suspected. Group rotation removes future access but cannot identify which member used a previously shared key and does not provide post-compromise security for later handshakes while the old key remains valid.
6. Treat every holder and every process able to read the PSK as equally authorized under the current model.

An app that starts from a password needs a purpose-built, reviewed password-authenticated provisioning design. HKDF does not increase source entropy and must not be used to present a password as a high-entropy PSK.

## Threat model: display-name spoofing inside a PSK group

### Adversary

Assume an attacker is a current or former group member who still knows the PSK, or has compromised one member and extracted it. The attacker can browse and advertise on the local network, initiate and accept TLS-PSK connections, and choose arbitrary valid discovery and handshake fields.

### Attack

The attacker advertises `pc-name=Alice` and either copies Alice's observed `pc-id` or chooses another identifier. After completing TLS with the shared group key, it sends a handshake that claims the same identity. The current coordinator accepts the handshake identity after protocol/version checks; no individual credential proves that the claimant is Alice.

### Impact

- UI and logs can attribute attacker-controlled messages to the wrong human or device.
- Name-based approval, authorization, audit, or safety decisions can be bypassed.
- Copying an identifier can interact with discovery maps and duplicate-connection resolution, causing confusion or availability loss for the legitimate peer.
- A unique-looking identifier does not solve the problem when it is self-asserted; uniqueness and authentication are separate properties.

### What remains protected

A network attacker without the PSK cannot complete the PSK-authenticated TLS connection or read/modify its application data. This does not reduce the insider threat because every PSK holder has the credential needed to create an independently valid connection.

### Required application posture today

Treat `Peer.displayName` as presentation text and `PeerIdentity.identifier` as a transport-local correlation value, not as an authorization principal. Do not grant privileges, approve sensitive actions, or create audit claims from either value alone. Apps requiring individual accountability should not use the current Network backend for sensitive operations until they add an independently reviewed identity layer or PeerConnectivity implements one of the modes below.

## Future trust options

These options are candidates, not promised APIs. A future design may support more than one because deployments have different provisioning and recovery needs.

### 1. HKDF-derived scoped or per-peer keys

Derive independent keys from a high-entropy root using HKDF with explicit, versioned context such as app identifier, environment, service type, group identifier, role, and canonical peer identifiers. Use authenticated, unambiguous context encoding and domain-separated labels.

Benefits:

- Limits accidental key reuse across services/environments.
- A distinct pairwise key can authenticate membership in a specific pair instead of an entire group.
- Supports targeted rotation when provisioning can distribute pairwise material.

Limits and design work:

- HKDF does not create identity or entropy; the root and the mapping from identifiers to derived keys must already be trusted.
- Deriving from self-asserted Bonjour/handshake identifiers would not provide identity binding.
- Both endpoints need an authenticated way to know the expected peer identity before choosing the key. Apple's PSK-selection callback can select among PSK identities, but the selection label is not itself proof of the endpoint's human/device identity.
- The protocol must specify salt, `info`, output length, canonical ordering for pairwise identifiers, versioning, key identifiers, storage, rotation, and migration behavior.

### 2. Per-peer identity binding above TLS

Give each installation or account a long-term signing key. During connection setup, exchange a public-key credential and sign a transcript containing at least both claimed peer identifiers, both fresh nonces, protocol/service context, and a binding to the established TLS channel where platform support permits. Accept the peer only after verifying the signature and app trust policy.

This can work over group TLS-PSK while adding individual identity, but it requires replay protection, downgrade protection, credential provisioning/revocation, secure private-key storage, and a precise connection-state gate so application data is not attributed before verification succeeds. Merely signing the display name is insufficient.

### 3. Certificate and pinning mode

Configure a local `sec_identity_t` containing a private key and certificate with `sec_protocol_options_set_local_identity`, then evaluate the peer trust with `sec_protocol_options_set_verify_block`. A deployment could use an app-specific CA, pinned certificate/public-key hashes, or another explicit trust-anchor policy.

The mode must define mutual authentication rather than assuming server-only validation is enough for a symmetric peer mesh. It also needs issuance, expiry, rotation, revocation, pin-set updates, recovery, and a rule binding the accepted certificate/public key to the protocol peer identifier. Disabling default trust evaluation without replacing it with a complete pinning policy would be insecure.

### 4. App-provided verifier

Allow an app to evaluate a structured peer credential or challenge result and return an authenticated principal (or reject) before a connection becomes visible as connected. This supports account systems, managed-device attestations, invitation credentials, or app-specific trust stores without forcing one PKI model into the framework.

A future verifier contract must specify:

- the authenticated inputs it receives, including channel-binding material if available;
- asynchronous completion, timeout, cancellation, and exactly-once semantics;
- the queue/executor used for callbacks;
- fail-closed behavior for errors and missing decisions;
- whether decisions are cached and how revocation invalidates them;
- separation of authenticated principal, mutable display name, and transport identifier;
- inbound and outbound symmetry; and
- when discovery/connection/data events become observable.

This is intentionally not a public API proposal yet.

## Recommended direction and security gates

1. Keep `.multipeerConnectivity` as the default and keep the Network backend experimental.
2. Immediately document 32-byte CSPRNG-generated PSKs and the group-membership boundary; do not imply that a PSK identity label identifies a peer.
3. Before calling the Network backend production-ready or making it the default, choose and security-review an individual identity mode. Pairwise HKDF-derived PSKs are suitable only where authenticated pair provisioning already exists; certificate/pinning or signed per-peer credentials provide clearer long-term identity for broader deployments.
4. Separate three concepts in the eventual protocol model: authenticated principal, stable transport identifier, and mutable display name.
5. Bind the accepted principal to the connection and require verification before registering the peer, emitting connected/data events, or using the identity in duplicate resolution.
6. Add negative tests for member spoofing, credential mismatch, replay, stale/revoked credentials, downgrade, verifier timeout/error, and identity changes across discovery and handshake.
7. Require a security review and on-device interoperability tests before exposing any new trust mode as stable public policy.

## Source and platform verification

The claims above were checked against:

- [`Sources/NetworkPeerTransport.swift`](Sources/NetworkPeerTransport.swift): current PSK setup uses `sec_protocol_options_add_pre_shared_key` with one app key and a fixed protocol label, and pins both the minimum and maximum protocol versions to TLS 1.2 with no protocol or plaintext fallback.
- [`Sources/PeerNetworkProtocol.swift`](Sources/PeerNetworkProtocol.swift): Bonjour and handshake identities contain self-asserted identifier/display-name fields and no proof of possession.
- [`Sources/NetworkPeerCoordinator.swift`](Sources/NetworkPeerCoordinator.swift): a valid protocol handshake identity is registered without an individual credential check.
- Apple SDK `Security.framework/Headers/SecProtocolOptions.h`: `sec_protocol_options_add_pre_shared_key` accepts a PSK plus its PSK identity; the same API surface provides PSK selection, local certificate identity, and trust verification callbacks.
- [TLS 1.3, RFC 8446 §2.2](https://www.rfc-editor.org/rfc/rfc8446.html#section-2.2): external PSKs need sufficient entropy; password-derived/low-entropy secrets permit dictionary attacks.
- [TLS 1.3, RFC 8446 §4.2.11](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.2.11): a PSK identity is a label for a key.
- [TLS 1.3, RFC 8446 Appendix E.7](https://www.rfc-editor.org/rfc/rfc8446.html#appendix-E.7): avoid cross-protocol PSK reuse.
- [HKDF, RFC 5869 §§3–4](https://www.rfc-editor.org/rfc/rfc5869.html#section-3): bind derivation to context using `info`; HKDF cannot amplify password entropy.

The TLS 1.3 references above inform general external-PSK key hygiene and future protocol design; they do not describe the current transport version. The current external-PSK transport requires exactly TLS 1.2. Apple header descriptions establish available platform mechanisms, not a complete PeerConnectivity protocol design. Each future option still needs focused platform prototyping and security review before implementation.
