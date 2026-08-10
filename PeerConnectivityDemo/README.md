# PeerConnectivity Demo

The expanded demo exposes both transport backends without changing the library default. Choose **Multipeer** or **Network**, then choose **Automatic** or **Require Invitation** before starting. Both backends support both connection behaviors using the same public APIs. The demo remembers each backend's choice while it runs; defaults preserve the existing walkthroughs: Multipeer uses **Automatic**, while Network uses **Require Invitation**. All combinations retain the connection-mode controls, peer status, typed message history, raw data and resource exercises, structured logs, troubleshooting guidance, and physical-test checklist.

## Connection behavior

- **Automatic** creates the selected backend's manager with `.automatic`, so discovered peers connect automatically.
- **Require Invitation** creates it with `.custom`. `PeerBrowserModel` supplies app-owned discovery state and the demo renders an explicit **Invite _peer name_** action for both backends.

### Require-invitation flow

1. Run the demo on two iOS simulators or devices on the same local network.
2. Select the same backend and **Require Invitation** on both instances, then tap **Start**.
3. Under **Peers**, tap the enabled **Invite _peer name_** action supplied from `PeerBrowserModel` discovery state.
4. Wait for the peer to report **Connected**.
5. Enter a message or ping, optionally choose a target, and tap **Send Typed Message**. The receiving instance records the `PeerMessage` in message history and the structured event log.

The Network backend deliberately uses `.unauthenticated` transport and labels this in the UI; use it only for non-sensitive local migration testing. Production apps should provide app-managed `.preSharedKey` material and an appropriate trust model. Multipeer remains the default backend and retains the backward-compatible default `PeerSecurityConfiguration`.

## Launch arguments

| Argument | Effect |
|---|---|
| `PCNetworkBackend` | Select the Network.framework backend. Without it, MultipeerConnectivity remains selected. |
| `PCAutoStart` | Start advertising and browsing after launch. |
| `PCDisplayName <name>` | Use a deterministic local display name. |

Example arguments for two instances:

```text
PCNetworkBackend PCAutoStart PCDisplayName Alice
PCNetworkBackend PCAutoStart PCDisplayName Bob
```

The backend and connection-behavior selectors are disabled while networking is running. Tap **Stop** before changing either setting. Network mode does not support the demo resource exercise; that action logs the backend's explicit unsupported-operation error.
