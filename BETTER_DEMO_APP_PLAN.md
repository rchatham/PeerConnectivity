# Better Demo App Plan

## Goal

Build a more useful PeerConnectivity demo app that can exercise the framework in real-world scenarios, provides a clearer UI for peers/messages/events, improves automated test coverage, and records auditable logs that can be exported from an installed iPhone app.

## Current State

- `PeerConnectivityDemo/ViewController.swift` contains the entire demo UI.
- The current demo has one start/stop button and one connection-status label.
- It initializes `PeerConnectionManager(serviceType: "local")`, listens with key `"configurationKey"`, and only handles `.devicesChanged`.
- `PeerConnectivityDemo/Info.plist` already includes local-network usage and Bonjour service declarations.
- Tests currently cover `PeerMessage` well, but framework lifecycle, observable behavior, peer modeling, and demo-oriented flows have minimal or no coverage.

## Product Requirements

### Demo UI

- Show local device/session state clearly.
- Provide explicit controls for:
  - Start / stop
  - Refresh
  - Advertising only
  - Browsing only
  - Advertising and browsing
- Show discovered and connected peers in a scannable list.
- Provide a simple compose/send flow for broadcasting a test message to connected peers.
- Show a chronological event log in-app.
- Keep the app dependency-free and UIKit-based unless intentionally changed later.

### Auditable Logs

- Record structured log entries for important app and framework events.
- Include at minimum:
  - Timestamp
  - Event kind
  - Human-readable detail
  - Relevant peer display names when available
  - Direction for send/receive events where applicable
- Provide a share/export button that opens `UIActivityViewController`.
- Export logs in a reviewer-friendly format, preferably JSON Lines or pretty JSON plus a plain-text summary.
- Avoid logging secrets, raw certificates, or large binary payloads by default.
- Keep logs local to the app until the user explicitly shares them.

### Testing

- Add targeted tests for pure Swift units first.
- Improve coverage around listener registration/removal and initial manager state.
- Keep tests deterministic and avoid requiring real MultipeerConnectivity devices where possible.
- Tests should remain XCTest-only with no third-party dependencies.

## Proposed Implementation Phases

### Phase 1 — Logging Model and Export Formatting

Files likely involved:

- `PeerConnectivityDemo/LogEntry.swift` (new)
- `PeerConnectivityDemo/LogStore.swift` (new, if useful)
- `PeerConnectivityDemo/ViewController.swift`

Tasks:

1. Add a small `LogEntry` model for timestamped structured events.
2. Add formatting helpers for human-readable text and JSON/JSONL export.
3. Add an in-memory log store with append, clear, and export methods.
4. Make sure event details avoid raw sensitive payloads.

Acceptance criteria:

- Logs can be appended consistently from UI and framework callbacks.
- Export output is deterministic enough to test.
- Share payload contains enough context to audit a demo session.

### Phase 2 — Demo UI Overhaul

Files likely involved:

- `PeerConnectivityDemo/ViewController.swift`
- `PeerConnectivityDemo/Base.lproj/Main.storyboard` only if storyboard wiring is needed; prefer programmatic UI for consistency with current app.

Tasks:

1. Replace the single-button UI with a structured UIKit interface.
2. Add sections for connection controls, peers, message composer, and event log.
3. Handle all `PeerConnectionEvent` cases and append log entries for each.
4. Keep UI updates on the main queue.
5. Add a share button for exporting logs.

Acceptance criteria:

- App clearly shows session status, peer discovery, connected peers, and recent events.
- User can start/stop/refresh and send a simple broadcast test message.
- User can share logs from a physical phone.

### Phase 3 — Demo Message Type

Files likely involved:

- `PeerConnectivityDemo/DemoMessage.swift` (new)
- `PeerConnectivityDemo/ViewController.swift`

Tasks:

1. Define a small `PeerMessage`-conforming demo message type.
2. Register an observer for the demo message type.
3. Log outgoing and incoming messages.
4. Surface received messages in the event log.

Acceptance criteria:

- Two installed demo apps can exchange a simple text message.
- Send and receive events are represented in auditable logs.

### Phase 4 — Test Coverage Improvements

Files likely involved:

- `PeerConnectivityTests/ObservableTests.swift` (new)
- `PeerConnectivityTests/PeerTests.swift` (new)
- `PeerConnectivityTests/PeerConnectivityTests.swift` (expand)
- Potentially demo log formatting tests if the demo target can be tested cleanly.

Tasks:

1. Add tests for `Observable<T>` and `MultiObservable<T>` listener behavior.
2. Add tests for `Peer` equality, hashing, status, and display name behavior.
3. Add tests for `PeerConnectionManager` initial state and listener removal APIs where feasible.
4. Add tests for log export formatting if the code can be placed in a testable target.

Acceptance criteria:

- New tests run under the existing Xcode test scheme.
- Tests avoid requiring live devices or real network discovery.
- Existing `PeerMessageTests` remain passing.

### Phase 5 — Physical Device Verification

Tasks:

1. Install the demo app on two iPhones, or one iPhone plus another compatible device if available.
2. Verify local network permissions flow.
3. Verify peer discovery and connection lifecycle.
4. Send messages in both directions.
5. Export logs from at least one phone and inspect the shared artifact.
6. Capture screenshots or a short screen recording for PR review if UI changes are submitted.

Acceptance criteria:

- The demo can demonstrate discovery, connection, messaging, and log export.
- Shared logs are readable and sufficient to audit the session.
- Visual artifacts are available for PR/MR review.

## Open Design Decisions

1. Log export format: JSON Lines, pretty JSON, plain text, or a bundled combination.
2. Log persistence: in-memory only for demo sessions, or persisted between app launches.
3. UI architecture: single `ViewController` with helper types, or split into view models/controllers.
4. Whether demo-only log types should live in the demo target or a library testable support target.
5. Whether to support selecting individual peers for messages in the first pass or broadcast only.

## Suggested First Commit Breakdown

1. `feat(demo): add auditable log model and export formatting`
2. `feat(demo): overhaul peer connectivity demo interface`
3. `feat(demo): add demo message send and receive flow`
4. `test: cover observable and peer model behavior`
5. `test: expand peer connection manager coverage`

## Verification Commands

```bash
xcodebuild test -workspace PeerConnectivity.xcworkspace \
  -scheme PeerConnectivity \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug

xcodebuild -workspace PeerConnectivity.xcworkspace \
  -scheme PeerConnectivity \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug build
```
