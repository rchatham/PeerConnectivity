//
//  BluetoothPeerTransportTests.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
import PeerConnectivity
@testable import PeerConnectivityBluetooth

/// Drives whole managers over a simulated radio: real coordinators, secure channels and
/// stream-backed connections, with Core Bluetooth replaced by bound stream pairs.
@available(iOS 13.0, macOS 10.15, *)
final class BluetoothPeerTransportTests : XCTestCase {

    private var managers : [PeerConnectionManager] = []

    override func tearDown() {
        managers.forEach { $0.stop() }
        managers.removeAll()
        super.tearDown()
    }

    // MARK: - Connecting over the simulated radio

    func testManagersWithTheSameKeyConnectAndExchangeData() {
        let radio = SimulatedBluetoothRadio()
        let security = PeerConnectionNetworkSecurity.preSharedKey(Data("group key".utf8))
        let alice = makeManager("Alice", security: security, radio: radio)
        let bob = makeManager("Bob", security: security, radio: radio)
        assertConnectsAndExchangesData(alice, bob)
    }

    func testManagersWithCertificatesConnectAndExchangeData() throws {
        let radio = SimulatedBluetoothRadio()
        let alice = makeManager("Alice", security: .certificate(identity: try PeerNetworkCertificateFixtures.identity(.alice)), radio: radio)
        let bob = makeManager("Bob", security: .certificate(identity: try PeerNetworkCertificateFixtures.identity(.bob)), radio: radio)
        assertConnectsAndExchangesData(alice, bob)
    }

    func testPeersThatFindEachOtherAtOnceSettleOnOneConnection() {
        let radio = SimulatedBluetoothRadio()
        let security = PeerConnectionNetworkSecurity.preSharedKey(Data("group key".utf8))
        let alice = makeManager("Alice", security: security, radio: radio)
        let bob = makeManager("Bob", security: security, radio: radio)
        let connected = expectation(description: "both sides connected")
        connected.expectedFulfillmentCount = 2
        connected.assertForOverFulfill = false
        [alice, bob].forEach { manager in
            manager.listenOn({ event in
                if case .devicesChanged(_, let peers) = event, !peers.isEmpty { connected.fulfill() }
            }, withKey: "test")
        }
        alice.start()
        bob.start()
        wait(for: [connected], timeout: 10)
        waitForEvents()
        XCTAssertEqual(alice.connectedPeers.map { $0.displayName }, ["Bob"])
        XCTAssertEqual(bob.connectedPeers.map { $0.displayName }, ["Alice"])
    }

    func testManagersWithDifferentKeysFindButNeverConnect() {
        let radio = SimulatedBluetoothRadio()
        let alice = makeManager("Alice", security: .preSharedKey(Data("one key".utf8)), radio: radio)
        let bob = makeManager("Bob", security: .preSharedKey(Data("another key".utf8)), radio: radio)
        let found = expectation(description: "peers still discover each other")
        found.assertForOverFulfill = false
        let connected = expectation(description: "no connection without the shared key")
        connected.isInverted = true
        [alice, bob].forEach { manager in
            manager.listenOn({ event in
                switch event {
                case .foundPeer: found.fulfill()
                case .devicesChanged(_, let peers) where !peers.isEmpty: connected.fulfill()
                default: break
                }
            }, withKey: "test")
        }
        alice.start()
        bob.start()
        wait(for: [found, connected], timeout: 3)
    }

    // MARK: - Lost-peer expiry

    func testPeerIsLostFiveSecondsAfterItsLastSighting() {
        let clock = TestClock()
        var browser : BluetoothPeerBrowserTransport?
        let manager = makeManager("Alice", security: .unauthenticated, radio: SimulatedBluetoothRadio(),
            connectionType: .custom, now: clock.now, browserCreated: { browser = $0 })
        var found = 0
        var lost = 0
        let lock = NSLock()
        manager.listenOn({ event in
            lock.lock(); defer { lock.unlock() }
            switch event {
            case .foundPeer: found += 1
            case .lostPeer: lost += 1
            default: break
            }
        }, withKey: "test")
        manager.startBrowsingOnly()

        let bob = PeerNetworkDiscoveryInfo(identity: PeerIdentity(identifier: UUID().uuidString, displayName: "Bob"))
        let peripheral = UUID()
        browser?.sighted(bob, on: peripheral)
        clock.advance(by: 4)
        browser?.sighted(bob, on: peripheral)
        clock.advance(by: 4.9)
        browser?.expireSightings()
        waitForEvents()
        lock.lock()
        XCTAssertEqual(found, 1, "a peer seen again is not found twice")
        XCTAssertEqual(lost, 0, "4.9 seconds after the last sighting")
        lock.unlock()

        clock.advance(by: 0.2)
        browser?.expireSightings()
        waitForEvents()
        lock.lock()
        XCTAssertEqual(lost, 1, "5.1 seconds after the last sighting")
        lock.unlock()

        browser?.sighted(bob, on: UUID())
        waitForEvents()
        lock.lock()
        XCTAssertEqual(found, 2, "found again after being lost, even from a rotated address")
        lock.unlock()
    }

    // MARK: - Failures reported to the app

    func testBluetoothOffIsReportedForBrowsingAndAdvertising() {
        let radio = SimulatedBluetoothRadio()
        radio.unavailable = .poweredOff
        let manager = makeManager("Alice", security: .unauthenticated, radio: radio)
        let reported = expectation(description: "both roles report Bluetooth off")
        reported.expectedFulfillmentCount = 2
        manager.listenOn({ event in
            guard case .error(let error) = event else { return }
            switch error as? PeerConnectionError {
            case .browsingFailed(let underlying)?, .advertisingFailed(let underlying)?:
                XCTAssertEqual(underlying as? PeerBluetoothError, .poweredOff)
                reported.fulfill()
            default:
                XCTFail("unexpected error \(error)")
            }
        }, withKey: "test")
        manager.start()
        wait(for: [reported], timeout: 3)
    }

    func testDiscoveryInfoTooLargeForOneAttributeFailsAdvertising() {
        let value = String(repeating: "v", count: 200)
        let manager = makeManager("Alice", security: .unauthenticated, radio: SimulatedBluetoothRadio(),
            discoveryInfo: ["a": value, "b": value, "c": value])
        let reported = expectation(description: "invalid discovery info reported")
        manager.listenOn({ event in
            guard case .error(let error) = event, case .invalidDiscoveryInfo? = error as? PeerConnectionError else { return }
            reported.fulfill()
        }, withKey: "test")
        manager.start()
        wait(for: [reported], timeout: 3)
    }

    // MARK: - Service layout and public entry point

    func testServiceUUIDIsStablePerServiceTypeAndWellFormed() {
        let first = BluetoothPeerService.serviceUUID(for: "chat")
        XCTAssertEqual(first, BluetoothPeerService.serviceUUID(for: "chat"))
        XCTAssertNotEqual(first, BluetoothPeerService.serviceUUID(for: "game"))
        XCTAssertEqual(first.data.count, 16)
        XCTAssertEqual(first.data[6] >> 4, 5, "version nibble")
        XCTAssertEqual(first.data[8] >> 6, 2, "variant bits")
    }

    func testIdentityPayloadRoundTripsAndRejectsBadInput() throws {
        let info = PeerNetworkDiscoveryInfo(identity: PeerIdentity(identifier: UUID().uuidString, displayName: "Alice"),
            appInfo: ["room": "lobby"])
        let payload = try XCTUnwrap(BluetoothPeerService.identityPayload(for: info))
        let decoded = try XCTUnwrap(BluetoothPeerService.discoveryInfo(fromIdentityPayload: payload))
        XCTAssertEqual(decoded.identity, info.identity)
        XCTAssertEqual(decoded.appInfo, ["room": "lobby"])

        XCTAssertNil(BluetoothPeerService.discoveryInfo(fromIdentityPayload: Data("not json".utf8)))
        XCTAssertNil(BluetoothPeerService.discoveryInfo(fromIdentityPayload: Data(count: 513)))
    }

    func testPublicInitializerSelectsTheBackendForTheChosenLinks() {
        // Not started: starting would ask the system for Bluetooth and local network access.
        let expectations : [(PeerConnectionLinks, PeerConnectionBackend)] = [
            (.bluetooth, .bluetooth),
            (.networkFramework, .networkFramework),
            (.all, .networkFrameworkAndBluetooth),
        ]
        for (links, backend) in expectations {
            let manager = PeerConnectionManager(serviceType: "bt-entry-\(links.rawValue)", links: links, displayName: "Alice")
            managers.append(manager)
            XCTAssertEqual(manager.backend, backend)
            XCTAssertEqual(manager.peer.displayName, "Alice")
        }
    }

    // MARK: - Helpers

    private func makeManager(_ name: String,
        security: PeerConnectionNetworkSecurity,
        radio: SimulatedBluetoothRadio,
        connectionType: PeerConnectionType = .automatic,
        discoveryInfo: PeerDiscoveryInfo? = nil,
        now: @escaping () -> Date = Date.init,
        browserCreated: ((BluetoothPeerBrowserTransport) -> Void)? = nil) -> PeerConnectionManager {
        let manager = PeerConnectionManager(serviceType: "bt-test",
            connectionType: connectionType,
            displayName: name,
            discoveryInfo: discoveryInfo,
            networkSecurity: security,
            transportFactory: .bluetooth(security: security, radio: radio.radio, now: now, browserCreated: browserCreated))
        managers.append(manager)
        return manager
    }

    private func assertConnectsAndExchangesData(_ alice: PeerConnectionManager,
        _ bob: PeerConnectionManager,
        file: StaticString = #filePath,
        line: UInt = #line) {
        let connected = expectation(description: "both sides connected")
        connected.expectedFulfillmentCount = 2
        connected.assertForOverFulfill = false
        let received = expectation(description: "Bob receives Alice's data")
        let payload = Data("over bluetooth".utf8)
        alice.listenOn({ event in
            if case .devicesChanged(_, let peers) = event, !peers.isEmpty { connected.fulfill() }
        }, withKey: "test")
        bob.listenOn({ event in
            switch event {
            case .devicesChanged(_, let peers) where !peers.isEmpty:
                connected.fulfill()
            case .receivedData(_, let data):
                XCTAssertEqual(data, payload, file: file, line: line)
                received.fulfill()
            default: break
            }
        }, withKey: "test")
        // One direction only, so exactly one channel exists. When both sides browse, each opens a
        // channel and the coordinator's tie-break may replace the first one admitted; see
        // `testPeersThatFindEachOtherAtOnceSettleOnOneConnection`.
        alice.startBrowsingOnly()
        bob.startAdvertisingOnly()
        wait(for: [connected], timeout: 10)
        XCTAssertEqual(alice.connectedPeers.map { $0.displayName }, ["Bob"], file: file, line: line)
        alice.sendData(payload)
        wait(for: [received], timeout: 10)
    }

    /// Manager events hop through observers asynchronously.
    private func waitForEvents() {
        let settled = expectation(description: "events delivered")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
    }
}

/// A controllable clock for lost-peer expiry.
private final class TestClock {
    private let lock = NSLock()
    private var current = Date(timeIntervalSinceReferenceDate: 0)

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(interval)
        lock.unlock()
    }
}

/// Replaces Core Bluetooth: advertising peripherals are sighted by started centrals with the
/// same service type, and opening a channel joins both sides with bound stream pairs.
@available(iOS 13.0, macOS 10.15, *)
final class SimulatedBluetoothRadio {

    final class Peripheral : BluetoothPeerAdvertising {
        let identifier = UUID()
        let serviceType : ServiceType
        let payload : Data
        let handlers : BluetoothPeerAdvertisingHandlers
        weak var radio : SimulatedBluetoothRadio?
        var isStarted = false
        var isAdvertising = false

        init(serviceType: ServiceType, payload: Data, handlers: BluetoothPeerAdvertisingHandlers, radio: SimulatedBluetoothRadio) {
            self.serviceType = serviceType
            self.payload = payload
            self.handlers = handlers
            self.radio = radio
        }

        func start() { radio?.update(self) { $0.isStarted = true } }
        func cancel() { radio?.update(self) { $0.isStarted = false; $0.isAdvertising = false } }
        func setAdvertising(_ isAdvertising: Bool) { radio?.update(self) { $0.isAdvertising = isAdvertising } }
    }

    final class Central : BluetoothPeerScanning {
        let serviceType : ServiceType
        let handlers : BluetoothPeerScanningHandlers
        weak var radio : SimulatedBluetoothRadio?
        var isScanning = false

        init(serviceType: ServiceType, handlers: BluetoothPeerScanningHandlers, radio: SimulatedBluetoothRadio) {
            self.serviceType = serviceType
            self.handlers = handlers
            self.radio = radio
        }

        func start() { radio?.startScanning(self) }
        func cancel() { radio?.lock.lock(); isScanning = false; radio?.lock.unlock() }
        func openChannel(to peripheral: UUID) { radio?.openChannel(from: self, to: peripheral) }
    }

    /// Set before starting to make both roles report Bluetooth as unavailable.
    var unavailable : PeerBluetoothError?
    fileprivate let lock = NSLock()
    private let queue = DispatchQueue(label: "SimulatedBluetoothRadio")
    private var peripherals : [Peripheral] = []
    private var centrals : [Central] = []
    private var channelOutputs : [OutputStream] = []

    /// Channels opened so far, including ones since closed.
    var openedChannelCount : Int {
        lock.lock(); defer { lock.unlock() }
        return channelOutputs.count / 2
    }

    /// Ends every channel on this radio and stops its advertisements reaching scanners, as
    /// turning the radio off would. Both ends see their input close.
    func severChannels() {
        lock.lock()
        let outputs = channelOutputs
        peripherals.forEach { $0.isAdvertising = false }
        lock.unlock()
        queue.sync { outputs.forEach { $0.close() } }
    }

    var radio : BluetoothPeerRadio {
        return BluetoothPeerRadio(
            makeAdvertising: { serviceType, payload, handlers in
                let peripheral = Peripheral(serviceType: serviceType, payload: payload, handlers: handlers, radio: self)
                self.lock.lock(); self.peripherals.append(peripheral); self.lock.unlock()
                return peripheral
            },
            makeScanning: { serviceType, handlers in
                let central = Central(serviceType: serviceType, handlers: handlers, radio: self)
                self.lock.lock(); self.centrals.append(central); self.lock.unlock()
                return central
            })
    }

    fileprivate func update(_ peripheral: Peripheral, _ change: (Peripheral) -> Void) {
        lock.lock()
        let wasStarted = peripheral.isStarted
        change(peripheral)
        // Like Core Bluetooth's single state update, report unavailability once, on start.
        let isStarting = !wasStarted && peripheral.isStarted && unavailable != nil
        lock.unlock()
        if isStarting, let unavailable = unavailable {
            peripheral.handlers.failed(.advertisingFailed(underlying: unavailable))
            return
        }
        announce()
    }

    fileprivate func startScanning(_ central: Central) {
        if let unavailable = unavailable {
            central.handlers.failed(.browsingFailed(underlying: unavailable))
            return
        }
        lock.lock()
        central.isScanning = true
        lock.unlock()
        announce()
    }

    /// Delivers one sighting of every advertising peripheral to every scanning central.
    private func announce() {
        lock.lock()
        let pairs = centrals.filter { $0.isScanning }.flatMap { central in
            peripherals.filter { $0.isStarted && $0.isAdvertising && $0.serviceType == central.serviceType }
                .map { (central, $0) }
        }
        lock.unlock()
        for (central, peripheral) in pairs {
            guard let info = BluetoothPeerService.discoveryInfo(fromIdentityPayload: peripheral.payload) else { continue }
            queue.async { central.handlers.sighted(peripheral.identifier, info) }
        }
    }

    fileprivate func openChannel(from central: Central, to identifier: UUID) {
        lock.lock()
        let peripheral = peripherals.first { $0.identifier == identifier && $0.isStarted }
        lock.unlock()
        guard let target = peripheral else {
            queue.async { central.handlers.channelFailed(identifier, nil) }
            return
        }
        var centralIn : InputStream?
        var peripheralOut : OutputStream?
        var peripheralIn : InputStream?
        var centralOut : OutputStream?
        Stream.getBoundStreams(withBufferSize: 4096, inputStream: &centralIn, outputStream: &peripheralOut)
        Stream.getBoundStreams(withBufferSize: 4096, inputStream: &peripheralIn, outputStream: &centralOut)
        lock.lock()
        channelOutputs.append(contentsOf: [peripheralOut!, centralOut!])
        lock.unlock()
        queue.async {
            target.handlers.channelOpened(BluetoothChannelStreams(inputStream: peripheralIn!, outputStream: peripheralOut!, owner: nil))
            central.handlers.channelOpened(identifier, BluetoothChannelStreams(inputStream: centralIn!, outputStream: centralOut!, owner: nil))
        }
    }
}
