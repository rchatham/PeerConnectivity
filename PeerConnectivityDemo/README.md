# PeerConnectivity Demo

The demo exposes both transport backends without changing the library default. Choose **Multipeer** for the existing automatic MultipeerConnectivity path or **Network** for Network.framework discovery with manual peer approval.

## Network manual-invite flow

1. Run the demo on two iOS simulators or devices on the same local network.
2. Select **Network** on both instances, then tap **Start networking**.
3. Select a row under **Discovered peers**. The rows are supplied by `PeerBrowserModel`.
4. Tap **Invite selected peer**.
5. After the row reports **Connected**, tap **Send typed ping**. The status text on the other instance confirms receipt of the `PeerMessage` payload.

The demo's Network path uses `.custom` so discovery and invitation remain visible. It deliberately uses `.unauthenticated` transport and labels this in the UI; use it only for non-sensitive local migration testing. Production apps should provide app-managed `.preSharedKey` material and an appropriate trust model.

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

The backend selector is disabled while networking is running. Stop networking before changing backends.
