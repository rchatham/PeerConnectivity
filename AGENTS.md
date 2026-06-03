# AGENTS.md — PeerConnectivity

Guidelines for AI coding agents working in this repository. This is a Swift framework
wrapping Apple's MultipeerConnectivity for Bluetooth/WiFi mesh networking.

## Build & Test Commands

### Build (Xcode — primary)

```bash
# Build the framework (iOS Simulator)
xcodebuild -workspace PeerConnectivity.xcworkspace \
  -scheme PeerConnectivity \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug build

# Build via Swift Package Manager (no test target in Package.swift)
swift build
```

### Run Tests

```bash
# Run all tests
xcodebuild test -workspace PeerConnectivity.xcworkspace \
  -scheme PeerConnectivity \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug

# Run a single test class
xcodebuild test -workspace PeerConnectivity.xcworkspace \
  -scheme PeerConnectivity \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PeerConnectivityTests/PeerMessageTests

# Run a single test method
xcodebuild test -workspace PeerConnectivity.xcworkspace \
  -scheme PeerConnectivity \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PeerConnectivityTests/PeerMessageTests/testSimpleMessageRoundTrip
```

### No Linter Configured

No SwiftLint or SwiftFormat is set up. Follow the style conventions below.

## Project Layout

```
Sources/                    # All library source (single SPM target)
PeerConnectivityTests/      # XCTest unit tests (Xcode-only target)
PeerConnectivityDemo/       # Demo iOS app
PeerPlayground.playground/  # Interactive examples
Package.swift               # SPM manifest (iOS 8+, macOS 10.10+, Swift 5)
PeerConnectivity.podspec    # CocoaPods spec (v0.5.4)
```

Key files: `PeerConnectionManager.swift` (630 lines, main public API),
`PeerConnectionResponder.swift` (event dispatch), `Peer.swift` (peer model).

## Code Style

### Imports

Order: `Foundation` first, then `MultipeerConnectivity`, then platform imports
wrapped in `#if os(iOS)` / `#elseif os(macOS)`. No blank lines between imports.
Zero third-party dependencies.

```swift
import Foundation
import MultipeerConnectivity
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
```

### Formatting

- **Indentation**: 4 spaces (no tabs)
- **Braces**: K&R / same-line opening brace (Swift standard)
- **Line length**: Soft limit ~120 chars; delegate signatures may be longer
- **Blank lines**: Single blank line between logical sections; double blank line
  occasionally separates major property groups
- **Space before colon in type annotations**: This codebase uses `let foo : Type`
  (non-standard but consistent — follow it)
- **Dictionary types**: Prefer `[String:Any]` (no spaces around colon in dict types)
- **Trailing commas**: Used in multi-line lists

### Access Control

Always explicit — write `internal` even though it's the default.

| Level | Usage |
|-------|-------|
| `public` | External API: `PeerConnectionManager`, `Peer`, `PeerConnectionEvent`, protocols, typealiases |
| `internal` | All wrapper types, observables, event producers, internal event enums |
| `fileprivate` | Stored properties of wrapper types, observer properties |
| `private` | Rare; test helpers only |

Special patterns used: `public fileprivate(set)` for read-only public properties,
`internal fileprivate(set)` for responder listeners.

### Naming Conventions

- **Types**: PascalCase — `PeerConnectionManager`, `PeerSessionEvent`
- **Related type naming pattern**: `Peer*` (wrapper), `Peer*EventProducer` (delegate bridge), `Peer*Event` (event enum)
- **Variables/properties**: camelCase — `connectionType`, `foundPeers`, `sessionObserver`
- **Functions**: camelCase with argument labels — `sendData(_:toPeers:)`, `listenOn(_:performListenerInBackground:withKey:)`
- **Enum cases**: camelCase with labeled associated values — `.devicesChanged(peer:connectedPeers:)`
- **Typealiases**: PascalCase — `ServiceType`, `PeerConnectionEventListener`
- **Static constants**: PascalCase — `PeerConnectivityKeys.CertificateListener`
- **IMPORTANT misspelling**: The codebase uses "Assisstant" (double 's') and "Dissmiss" intentionally. Maintain these in existing type/method names for API compatibility.

### Documentation

- **File headers**: Every file has the standard Xcode header (filename, project, author, copyright)
- **Public APIs**: Use `/** */` multi-line doc comments with `- parameter name:` and `- Returns:` format
- **Enum cases**: Use `/** */` doc comments
- **Internal helpers**: Use `///` single-line doc comments
- **Section markers**: `// MARK:` and `// MARK: -` to organize code within files
- **Suppressed docs**: Use `/// :nodoc:` for boilerplate conformances (Hashable, Equatable)

### Error Handling

```swift
// Pattern 1 (most common): do/catch with NSLog
do {
    try session.send(data, toPeers: peers, with: .reliable)
} catch let error {
    NSLog("%@", "Error sending data: \(error)")
}

// Pattern 2: try? for optional/silent failure
guard let data = try? NSKeyedArchiver.archivedData(...) else { return }

// Pattern 3: rethrow
do { return try session.sendDataStream(name, toPeer: peer) }
catch let error { throw error }
```

No custom Error types — uses system errors. Logging via `NSLog("%@", ...)`.

### Closures & Callbacks

- Use `[weak self]` in most observer closures
- Use `[unowned self]` only when self is guaranteed alive (`.automatic` connection type observers)
- Completion handlers as optional closures with default nil: `func start(_ completion: (()->Void)? = nil)`
- Mark escaping closures: `@escaping PeerConnectionEventListener`
- Typealiases for listener types: `typealias Observer = (T) -> Void`

### Extensions

- Use extensions for protocol conformance: `extension Peer : Hashable, Equatable { ... }`
- Use extensions for logical grouping within files (PeerConnectionManager has multiple)
- Note the space before colon: `extension Peer : Protocol` (matches codebase style)

### Platform Conditionals

Wrap platform-specific code in `#if os(iOS)` / `#elseif os(macOS)` / `#endif`.
Used for imports, browser view controller (iOS only), and device name access.

### Switch Statements

Internal enum switches use `default: break` rather than exhaustive case matching.

### Deprecation

Mark deprecated methods with `@available(*, deprecated, message: "...")`.

## Architecture

**Event pipeline**: MC Delegate -> EventProducer (NSObject) -> Observable -> PeerConnectionManager -> MultiObservable -> PeerConnectionResponder -> User listeners.

When adding features: (1) add internal event enum case, (2) handle in EventProducer
delegate method, (3) add `PeerConnectionEvent` case, (4) transform in
`PeerConnectionManager.start()` observer blocks.

## Testing

- Framework: XCTest (no third-party test libs)
- Import: `@testable import PeerConnectivity`
- Test naming: `testDescriptiveCamelCaseName` (no underscores)
- Use `// MARK: -` to organize test sections
- Define test helper types (e.g., mock message structs) at file scope above test class
- Helper methods: `private func` with doc comments (`///`)
- Assertions: `XCTAssertEqual`, `XCTAssertNotNil`, `XCTAssertNil`, `XCTAssertTrue`, `XCTFail`
- Use `throws` on test methods that call throwing code
- Test coverage is minimal — add tests when modifying existing code

## Important Notes

1. **Read before editing** — always read relevant files before making changes
2. **Backward compatibility** — this is a published library (CocoaPods/Carthage/SPM); avoid breaking changes
3. **No force pushes to master**
4. **Maintain the Observable/EventProducer pattern** for new features
5. **Threading**: Event listeners can run on background threads via `performListenerInBackground`; use `DispatchQueue.main.async` for UI work
6. **Zero dependencies** — do not add third-party deps
7. **Refer to CLAUDE.md** for additional architectural context and component hierarchy
