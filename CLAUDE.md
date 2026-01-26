# CLAUDE.md - PeerConnectivity

This document provides guidance for AI assistants working with the PeerConnectivity codebase.

## Project Overview

PeerConnectivity is a functional Swift wrapper for Apple's MultipeerConnectivity framework. It provides a lightweight, easy-to-use API for mesh networking over Bluetooth and WiFi, abstracting away the complexity and edge cases of the underlying framework.

- **Language**: Swift 5.0
- **Platform**: iOS 8.0+
- **Framework**: MultipeerConnectivity
- **Author**: Reid Chatham
- **License**: MIT
- **Current Version**: 0.5.4

## Codebase Structure

```
PeerConnectivity/
├── Sources/                          # Main library source files
│   ├── PeerConnectionManager.swift   # Main public API (entry point)
│   ├── Peer.swift                    # Peer model representing network users
│   ├── PeerSession.swift             # MCSession wrapper
│   ├── PeerBrowser.swift             # MCNearbyServiceBrowser wrapper
│   ├── PeerAdvertiser.swift          # MCNearbyServiceAdvertiser wrapper
│   ├── PeerBrowserAssisstant.swift   # Browser assistant for invite-only mode
│   ├── PeerAdvertiserAssisstant.swift # Advertiser assistant for invite-only mode
│   ├── PeerConnectionResponder.swift # Event dispatching and listener management
│   ├── Observable.swift              # Simple observable pattern implementation
│   ├── MultiObservable.swift         # Keyed observable with multiple listeners
│   └── *EventProducer.swift          # Delegate-to-observable bridges
├── PeerConnectivityTests/            # Unit tests
├── PeerConnectivityDemo/             # Demo iOS application
├── PeerPlayground.playground/        # Interactive playground examples
├── PeerConnectivity.xcodeproj/       # Xcode project
├── PeerConnectivity.xcworkspace/     # Xcode workspace
├── PeerConnectivity.podspec          # CocoaPods spec
└── Package.swift                     # Swift Package Manager manifest
```

## Architecture

### Design Patterns

1. **Observable Pattern**: Core event-driven architecture using `Observable<T>` and `MultiObservable<T>` classes
2. **Event Producer Pattern**: Each MultipeerConnectivity delegate is wrapped by an EventProducer that converts delegate callbacks into observable events
3. **Functional Wrapper**: Provides a functional interface over imperative delegate callbacks

### Component Hierarchy

```
PeerConnectionManager (public API)
├── PeerSession (MCSession wrapper)
├── PeerBrowser (MCNearbyServiceBrowser wrapper)
├── PeerBrowserAssisstant (MCBrowserViewController wrapper)
├── PeerAdvertiser (MCNearbyServiceAdvertiser wrapper)
├── PeerAdvertiserAssisstant (MCAdvertiserAssistant wrapper)
└── PeerConnectionResponder (listener management)
```

### Event Flow

1. MultipeerConnectivity delegate callbacks → EventProducer
2. EventProducer → Observable (internal events)
3. Observable → PeerConnectionManager (event transformation)
4. PeerConnectionManager → MultiObservable (PeerConnectionEvent)
5. MultiObservable → PeerConnectionResponder → User listeners

### Key Types

- **`PeerConnectionManager`**: Main entry point; manages session lifecycle, sending data, and event listening
- **`Peer`**: Struct representing a network peer with display name and connection status
- **`PeerConnectionEvent`**: Enum of all events (`.started`, `.devicesChanged`, `.receivedData`, `.receivedEvent`, etc.)
- **`PeerConnectionType`**: Connection mode enum (`.automatic`, `.inviteOnly`, `.custom`)
- **`ServiceType`**: Type alias for `String` representing the service channel name

## Code Conventions

### Access Control

- `public`: External API (PeerConnectionManager methods, Peer, PeerConnectionEvent)
- `internal`: Library internals (sessions, browsers, advertisers, observables)
- `fileprivate`: Implementation details within files

### Naming Conventions

- Classes/Structs: PascalCase (e.g., `PeerConnectionManager`)
- Event producers: `Peer*EventProducer` pattern
- Event enums: `Peer*Event` pattern
- Typealiases: PascalCase (e.g., `ServiceType`, `PeerConnectionEventListener`)

### File Organization

Each source file follows this structure:
1. Header comment with file name, project, author, and copyright
2. Imports
3. Type definitions (enums, typealiases)
4. Main class/struct definition
5. Extensions for protocol conformance or logical grouping

### Documentation

- Use `/** */` documentation comments for public APIs
- Parameters documented with `- parameter name:` format
- Returns documented with `- Returns:` format

### Threading

- Event listeners can optionally run on background threads via `performListenerInBackground` parameter
- Main thread dispatch is used for UI-related operations (`DispatchQueue.main.async`)

## Development Workflow

### Building

```bash
# Open in Xcode
open PeerConnectivity.xcworkspace

# Or build via command line
xcodebuild -workspace PeerConnectivity.xcworkspace -scheme PeerConnectivity
```

### Testing

```bash
# Run tests via Xcode or command line
xcodebuild test -workspace PeerConnectivity.xcworkspace -scheme PeerConnectivity -destination 'platform=iOS Simulator,name=iPhone 8'
```

Test files are in `PeerConnectivityTests/`. The test framework is XCTest.

### Demo App

The `PeerConnectivityDemo` project demonstrates basic usage:
- Creating a `PeerConnectionManager`
- Starting/stopping networking
- Listening for device connection changes

### Package Managers

- **CocoaPods**: `pod 'PeerConnectivity', '~> 0.5.4'`
- **Carthage**: `github "rchatham/PeerConnectivity"`
- **Swift Package Manager**: Basic Package.swift available

## Common Tasks

### Adding New Event Types

1. Add case to relevant internal event enum (e.g., `PeerSessionEvent`)
2. Handle in EventProducer delegate method
3. Add corresponding case to `PeerConnectionEvent` enum
4. Transform in `PeerConnectionManager.start()` observer blocks

### Modifying Connection Behavior

Connection behavior is determined by `PeerConnectionType`:
- `.automatic`: Auto-browse and auto-accept invitations (configured in `start()`)
- `.inviteOnly`: Uses browser/advertiser assistants
- `.custom`: No default behavior; user implements all logic

### Working with Observers

```swift
// Adding an observer (internal)
observer.addObserver { event in
    // Handle event
}

// Adding a keyed listener (via responder)
responder.addListener({ event in
    // Handle event
}, forKey: "myKey")
```

## Key Files for Common Changes

| Task | Primary Files |
|------|---------------|
| API changes | `Sources/PeerConnectionManager.swift` |
| Event types | `Sources/PeerConnectionResponder.swift` |
| Peer model | `Sources/Peer.swift` |
| Session handling | `Sources/PeerSession.swift`, `Sources/PeerSessionEventProducer.swift` |
| Discovery | `Sources/PeerBrowser.swift`, `Sources/PeerAdvertiser.swift` |
| Observable pattern | `Sources/Observable.swift`, `Sources/MultiObservable.swift` |

## Notes for AI Assistants

1. **Read before editing**: Always read relevant files before making changes
2. **Maintain patterns**: Follow the existing Observable/EventProducer pattern for new features
3. **Access levels**: Keep internal components `internal`, only expose necessary public API
4. **Threading safety**: Be mindful of main thread requirements for UI updates
5. **Backward compatibility**: This is a published library; avoid breaking API changes
6. **Documentation**: Maintain documentation comments for public APIs
7. **Spelling note**: The codebase uses "Assisstant" (with double 's') - maintain this for consistency even though it's misspelled

## Dependencies

- **MultipeerConnectivity.framework**: Apple's peer-to-peer networking framework (system)
- **UIKit**: For `UIDevice.current.name` and `UIViewController` (browser VC)

No third-party dependencies are used.

## Version History

See `CHANGELOG.md` for version history. Key milestones:
- 0.4.1: Swift 3 and iOS 10 compatibility
- 0.5.0: Changed `AnyObject` to `Any`
- 0.5.1: Lowered iOS target to 8.0+
- 0.5.4: Added listening for nearby devices changed
- 0.6.0: Updated to Swift 5.0
