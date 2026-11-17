# BLE L2CAP spike

Feasibility prototype for a Bluetooth LE transport. **Not a shipped feature**: the types in
`Sources/BLEL2CAP/` are `internal`, nothing in `PeerConnectionManager` uses them, and the
public API is unchanged.

## What it does

- `BLEL2CAPAdvertiser` (peripheral): publishes an L2CAP channel, exposes the PSM in a read-only
  GATT characteristic, advertises the service UUID.
- `BLEL2CAPBrowser` (central): scans for the service, connects, reads the PSM, opens the channel.
- `BLEL2CAPChannelStream`: sends and receives `PeerNetworkFrame`s (the Network backend's
  1-byte kind + 4-byte length framing) over the channel's streams.

There is no encryption or authentication. The channel is opened with `withEncryption: false`,
so nothing here may carry a real conversation.

## Running the test app

Two physical devices are needed; the Simulator has no Bluetooth.

```bash
cd Spikes/BLEL2CAPSpike
xcodegen generate
xcodebuild -project BLEL2CAPSpike.xcodeproj -scheme BLEL2CAPSpike \
  -destination 'id=<DEVICE_ID>' -allowProvisioningUpdates build
```

Start the peripheral first, then the central:

```bash
xcrun devicectl device process launch --device <A> com.hermes.spike.blel2cap -- -role peripheral
xcrun devicectl device process launch --device <B> com.hermes.spike.blel2cap -- -role central -soak 120
```

The central times discovery and connection, measures round trips for a ~1 KB `PeerMessage`-shaped
JSON frame, measures throughput, then pings once a second for `-soak` seconds so either app can be
backgrounded. Each device writes `Documents/ble-spike-<role>.json`:

```bash
xcrun devicectl device copy from --device <B> --domain-type appDataContainer \
  --domain-identifier com.hermes.spike.blel2cap \
  --source Documents/ble-spike-central.json --destination ./central.json
```

`BLEL2CAPSpikeNoBG` (`com.hermes.spike.blel2cap.nobg`) is the same app without the
`bluetooth-central` / `bluetooth-peripheral` background modes.
