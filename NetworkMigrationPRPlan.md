# Network Framework Migration PR Plan

This plan breaks the remaining MultipeerConnectivity-to-Network migration into independently reviewable PRs. Each PR should be complete, simple, reviewed, tested, and mergeable on its own.

## Guardrails

- Keep current MultipeerConnectivity behavior as the default until Network parity is proven.
- Keep Network connection policy values internal until the backend has enough device/CI validation to justify stable public configuration semantics.
- Preserve public API/source compatibility where practical; deprecate MC-specific APIs before removing or replacing them.
- Avoid workaround layers. Add an abstraction only when it replaces an existing dependency surface or removes duplicated logic.
- Prefer simple, direct implementations over compatibility shims.
- Tests for a behavior change belong in the same PR and commit as the behavior change.
- Every PR must update docs/PR description so the branch state is holistic.

## Per-PR Automation Loop

1. `scout`: inspect relevant code and summarize constraints.
2. `planner`: produce the smallest viable implementation plan.
3. `worker`: implement the approved slice only.
4. `test-writer`: add focused unit, integration, or UI tests.
5. `reviewer`: review correctness, API compatibility, and simplicity.
6. `security-reviewer`: review security/privacy; use the strongest available Claude/Fable model via Claude Code when available for transport, TLS, UI, or untrusted-input changes.
7. Run verification:
   - `swift test`
   - `xcodebuild test -project PeerConnectivity.xcodeproj -scheme PeerConnectivity -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -configuration Debug`
8. Address findings and repeat until reviewers report no blocking findings.
9. Commit atomically, push, update PR description, and re-run the review loop.

## PR Series

### PR 1: CI and platform baseline

- Add GitHub Actions for Swift Package and Xcode project tests.
- Align package and podspec deployment targets with Network framework availability: iOS 13+ and macOS 10.15+.
- Link migration documentation from the README.
- No runtime behavior changes.

Acceptance criteria:
- `swift test` passes locally and in CI.
- Xcode project tests pass locally and in CI.
- README badges and deployment target docs match package/podspec declarations.

### PR 2: Thread-safe neutral event pipeline

- Serialize event delivery where Network callbacks enter the existing observable/event pipeline.
- Keep public `PeerConnectionEvent` behavior unchanged.
- Add concurrency-focused tests for listener registration, removal, and delivery ordering.

### PR 3: Network coordinator as transport

- Make `NetworkPeerCoordinator` satisfy the existing internal transport seams.
- Keep MultipeerConnectivity as the default factory.
- Add factory and manager tests proving both backends can be constructed without public behavior changes.

### PR 4: Opt-in Network backend

- Add a non-breaking backend selector, defaulting to MultipeerConnectivity.
- Wire the Network backend behind explicit opt-in only.
- Define `.custom`, `.automatic`, and `.inviteOnly` behavior for the Network backend.
- Add integration-style tests for discovery, connection, and data events.

### PR 5: Network data parity and hardening

- Complete bidirectional reliable data parity for `PeerMessage` use cases.
- Add handshake timeout, idle timeout, connection caps, and discovery caps.
- Keep policy values internal until their defaults are validated across CI and device testing.
- Keep TLS enabled and add app-configurable identity or PSK verification before public Network use.
- Add malformed-frame, oversized-frame, timeout, and cap tests.

### PR 6: Public API migration and deprecations

- Add framework-neutral public accessors where MC types currently leak through.
- Deprecate MC-specific APIs that block a complete migration, including `multipeerSession`, stream APIs, resource APIs, and browser-controller APIs where needed.
- Document replacement paths and compatibility behavior.

### PR 7: Simplification/refactor pass

- Remove prototype scaffolding and dead branches created during migration.
- Collapse any abstractions that no longer carry their weight.
- Require a clear justification for any new layer that remains.
- Prefer net LOC reduction unless tests or docs intentionally increase coverage.

### PR 8: SwiftUI browser replacement

- Add `PeerBrowserView` and `PeerBrowserModel` driven by framework-neutral discovery and connection events.
- Use SwiftUI as the primary browser implementation.
- Provide UIKit bridging through `UIHostingController` or representable wrappers where compatibility requires it.
- Retain and deprecate old `MCBrowserViewController`-specific paths as compatibility shims only.
- Add SwiftUI/UI tests for peer listing, selection, cancellation, and connection state updates.

### PR 9: End-to-end automation and UI testing

- Add a loopback/local integration harness where possible.
- Add XCUITest coverage for the SwiftUI browser and demo app smoke paths.
- Add CI automation for stable smoke tests.
- Document manual device checks for Bonjour and Local Network privacy prompts.

### PR 10: Docs and release prep

- Update README, migration guide, Info.plist notes, backend-selection docs, and CHANGELOG.
- Document unsupported or deprecated MC-specific APIs.
- Prepare versioning notes for the deployment-target bump and Network backend opt-in.

## Required Security Gates

Security review is mandatory for PRs that change:

- Network listener/connection setup.
- TLS identity, PSK, trust evaluation, or handshake payloads.
- Untrusted input parsing, frame decoding, or peer identity validation.
- SwiftUI browser input, peer selection, or invite flows.
- Public backend selection or default backend behavior.

Before the Network backend is publicly selectable, peer authentication must be explicit rather than relying on self-asserted display names or unauthenticated handshakes.
