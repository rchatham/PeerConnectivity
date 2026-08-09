# PeerConnectivity Demo

The expanded demo exposes both transport backends without changing the library default. Choose **Multipeer** for automatic MultipeerConnectivity invitations or **Network** for Network.framework discovery with manual peer approval. Both modes retain the connection-mode controls, peer status, typed message history, raw data and resource exercises, structured logs, troubleshooting guidance, and physical-test checklist.

## Network manual-invite flow

1. Run the demo on two iOS simulators or devices on the same local network.
2. Select **Network** on both instances, then tap **Start**.
3. Under **Peers**, tap the enabled **Invite _peer name_** action supplied from `PeerBrowserModel` discovery state.
4. Wait for the peer to report **Connected**.
5. Enter a message or ping, optionally choose a target, and tap **Send Typed Message**. The receiving instance records the `PeerMessage` in message history and the structured event log.

The demo's Network path uses `.custom` so discovery and invitation remain visible. It deliberately uses `.unauthenticated` transport and labels this in the UI; use it only for non-sensitive local migration testing. Production apps should provide app-managed `.preSharedKey` material and an appropriate trust model. Multipeer mode continues to use `.automatic` with the backward-compatible default `PeerSecurityConfiguration`.

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

The backend selector is disabled while networking is running. Tap **Stop** before changing backends. Network mode does not support the demo resource exercise; that action logs the backend's explicit unsupported-operation error.
