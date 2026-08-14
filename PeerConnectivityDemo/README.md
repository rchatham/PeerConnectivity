# PeerConnectivity Demo

The demo exposes both transport backends, connection behavior, and backend-specific security without changing library defaults. Choose **Multipeer** or **Network**, **Automatic** or **Require Invitation**, and a security mode before starting. Each backend remembers its choices while the app runs. Security and connection behavior are independent, and all related controls are disabled while networking runs.

## Security

### MultipeerConnectivity

- **Compatible** maps to `PeerSecurityConfiguration.default` (optional encryption).
- **Require Encryption** maps to `.encrypted` (required session encryption).

Neither mode authenticates individual peers in this demo. The manager has no local certificate identity and accepts all remote certificates, so even required encryption remains vulnerable to man-in-the-middle attacks.

### Network.framework

- **Unauthenticated** maps to `.unauthenticated` plain TCP and is only for non-sensitive local testing.
- **TLS Shared Key** maps to `.preSharedKey` only after strict Base64 validation succeeds.

TLS input rejects whitespace and malformed Base64 and must decode to at least 32 bytes. Invalid input displays an inline error and blocks **Start**; it never silently downgrades to unauthenticated transport. TLS-PSK authenticates membership in the shared-key group, not an individual person, device, account, or installation. Both peers must use identical key bytes.

**Generate Test Key** creates 32 bytes with `SecRandomCopyBytes`. The secure field disables autocorrection, spell checking, smart substitutions, and password autofill. Key material stays in memory, is excluded from logs/status/accessibility/export, and is never placed in Bonjour metadata. **Stop** preserves the current selection and key for restart. **Reset Demo** drops the demo's key references; this is not a claim of secure memory erasure.

Enter an identical key manually on both instances or use the debug-only launch argument below. The demo intentionally provides no copy/export action for keys.

## Connection behavior

- **Automatic** creates the selected backend's manager with `.automatic`.
- **Require Invitation** creates it with `.custom`; `PeerBrowserModel` supplies app-owned discovery state and explicit **Invite _peer name_** actions.

The manager keeps `invitationPolicy: .acceptAll`; the selector remains an independent connection-flow choice for both security modes and both backends.

The app target declares `NSLocalNetworkUsageDescription` and `_local._tcp` in `NSBonjourServices`, matching `serviceType: "local"`. Adopting apps must declare equivalent values for every service type in their own target.

## Launch arguments

| Argument | Effect |
|---|---|
| `PCNetworkBackend` | Select Network.framework. Without it, MultipeerConnectivity remains selected. |
| `PCAutoStart` | Start advertising and browsing after launch. Invalid TLS input still blocks Start. |
| `PCDisplayName <name>` | Use a deterministic local display name. |
| `PCNetworkPSKBase64 <value>` | **Debug builds only:** select Network TLS and validate the supplied Base64 key. |

Example for two debug instances (replace the placeholder with the same test value on each process):

```text
PCNetworkBackend PCNetworkPSKBase64 <test-base64> PCAutoStart PCDisplayName Alice
PCNetworkBackend PCNetworkPSKBase64 <test-base64> PCAutoStart PCDisplayName Bob
```

Process arguments can be inspected by local tooling and are not production secret storage. This argument is only a debug test-transfer convenience. Never place a production key in arguments, source, screenshots, logs, or the app bundle.

## Validation flow

1. Run two instances and select the same backend, security mode, and compatible connection behavior.
2. For Network TLS, enter the same valid 32+-byte Base64 key on both instances.
3. Tap **Start**. For **Require Invitation**, tap an enabled invite action after discovery.
4. Wait for **Connected**, then exchange typed messages or raw data.
5. Confirm malformed/short/mismatched keys do not establish a session and no key material appears in logs.

Use physical devices for Local Network permission and release-topology validation. Keep Wi-Fi enabled. Network.framework's peer-to-peer opt-in does not guarantee a particular interface and is not a Bluetooth-only transport. Network mode does not support the demo resource exercise; that action reports the existing unsupported-operation error.

The two backends are not wire-compatible. This demo requires both peers to select the same backend and includes no bridge or relay code. See the [Network backend guide](../NetworkBackendGuide.md) for production guidance and limitations.
