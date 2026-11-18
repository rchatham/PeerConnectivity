//
//  CombinedPeerTransportTests.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
import Security
import PeerConnectivity
@testable import PeerConnectivityBluetooth

@available(iOS 13.0, macOS 10.15, *)
final class CombinedPeerTransportTests : XCTestCase {

    private var managers : [PeerConnectionManager] = []

    override func tearDown() {
        managers.forEach { $0.stop() }
        managers.removeAll()
        super.tearDown()
    }

    // MARK: - End to end over two simulated radios

    func testPeerOnBothLinksIsReportedOnceAndStaysConnectedWhenOneLinkDrops() {
        let wifi = SimulatedBluetoothRadio()
        let bluetooth = SimulatedBluetoothRadio()
        let alice = makeManager("Alice", links: [wifi, bluetooth])
        let bob = makeManager("Bob", links: [wifi, bluetooth])
        let aliceEvents = EventLog(alice)
        let bobEvents = EventLog(bob)

        // Alice invites, so each link carries exactly one channel.
        alice.startBrowsingOnly()
        bob.startAdvertisingOnly()
        waitUntil("both links opened") { wifi.openedChannelCount >= 1 && bluetooth.openedChannelCount >= 1 }
        waitUntil("both sides connected") { aliceEvents.connections == 1 && bobEvents.connections == 1 }
        settle()
        XCTAssertEqual(aliceEvents.found, 1, "one peer, however many links see it")
        XCTAssertEqual(aliceEvents.connections, 1)
        XCTAssertEqual(bobEvents.connections, 1)

        wifi.severChannels()
        settle()
        XCTAssertEqual(aliceEvents.disconnections + bobEvents.disconnections, 0, "Bluetooth still carries the peer")
        XCTAssertEqual(alice.connectedPeers.map { $0.displayName }, ["Bob"])

        let payload = Data("after wifi dropped".utf8)
        let received = expectation(description: "data arrives over the remaining link")
        bob.listenOn({ event in
            if case .receivedData(_, let data) = event, data == payload { received.fulfill() }
        }, withKey: "received")
        alice.sendData(payload)
        wait(for: [received], timeout: 5)

        bluetooth.severChannels()
        waitUntil("disconnected once the last link drops") { aliceEvents.disconnections == 1 && bobEvents.disconnections == 1 }
        settle()
        XCTAssertEqual(aliceEvents.disconnections, 1)
        XCTAssertEqual(bobEvents.disconnections, 1)
    }

    func testInviteOnlyAppAnswersOneInvitationForBothLinks() {
        let wifi = SimulatedBluetoothRadio()
        let bluetooth = SimulatedBluetoothRadio()
        let alice = makeManager("Alice", links: [wifi, bluetooth], connectionType: .custom)
        let bob = makeManager("Bob", links: [wifi, bluetooth], connectionType: .inviteOnly)
        let bobEvents = EventLog(bob)
        let lock = NSLock()
        var invitations = 0
        bob.listenOn({ event in
            guard case .receivedInvitation(_, _, let handler) = event else { return }
            lock.lock(); invitations += 1; lock.unlock()
            handler(true)
        }, withKey: "answer")
        alice.listenOn({ event in
            if case .foundPeer(let peer) = event { alice.invitePeer(peer) }
        }, withKey: "invite")

        alice.startBrowsingOnly()
        bob.startAdvertisingOnly()
        waitUntil("both links opened") { wifi.openedChannelCount >= 1 && bluetooth.openedChannelCount >= 1 }
        waitUntil("connected") { bobEvents.connections == 1 }
        settle()
        lock.lock()
        XCTAssertEqual(invitations, 1, "the app answers once per peer")
        lock.unlock()

        wifi.severChannels()
        settle()
        XCTAssertEqual(bobEvents.disconnections, 0, "the second link was admitted with the first answer")
    }

    // MARK: - Merge rules with fake links

    func testConnectionChangesAreVisibleOnlyForTheFirstAndLastLink() {
        let harness = SessionHarness()
        let bob = remotePeer("Bob")
        harness.push(.devicesChanged(peer: bob.with(.connected), connectedPeers: []), link: 0)
        harness.push(.devicesChanged(peer: bob.with(.connected), connectedPeers: []), link: 1)
        harness.push(.devicesChanged(peer: bob.with(.notConnected), connectedPeers: []), link: 0)
        harness.push(.devicesChanged(peer: bob.with(.notConnected), connectedPeers: []), link: 1)
        let statuses = harness.output(count: 2).compactMap { event -> Peer.Status? in
            guard case .devicesChanged(let peer, _) = event else { return nil }
            return peer.status
        }
        XCTAssertEqual(statuses, [.connected, .notConnected])
    }

    func testSecondInvitationWaitsForTheAppsFirstAnswer() {
        let harness = SessionHarness()
        let bob = remotePeer("Bob")
        let answers = AnswerLog()
        harness.push(.didReceiveInvitation(peer: bob, context: nil, handler: answers.record("first")), link: 0)
        harness.push(.didReceiveInvitation(peer: bob, context: nil, handler: answers.record("second")), link: 1)
        guard case .didReceiveInvitation(_, _, let appHandler)? = harness.output(count: 1).first else {
            return XCTFail("the app is asked once")
        }
        appHandler(true)
        XCTAssertEqual(answers.values, ["first": true, "second": true])
    }

    func testInvitationJustAfterTheAppAnsweredReusesTheAnswer() {
        // The first link has not reported connected yet when the second link's invitation arrives.
        let harness = SessionHarness()
        let bob = remotePeer("Bob")
        let answers = AnswerLog()
        harness.push(.didReceiveInvitation(peer: bob, context: nil, handler: answers.record("first")), link: 0)
        guard case .didReceiveInvitation(_, _, let appHandler)? = harness.output(count: 1).first else {
            return XCTFail("the app is asked once")
        }
        appHandler(false)
        harness.push(.didReceiveInvitation(peer: bob, context: nil, handler: answers.record("second")), link: 1)
        waitUntil("answered") { answers.values["second"] != nil }
        XCTAssertEqual(answers.values, ["first": false, "second": false], "a decline covers every link too")
        harness.assertNoMoreOutput()
    }

    func testAcceptedCertificateCoversASecondLinkBeforeTheFirstReportsConnected() throws {
        let harness = SessionHarness()
        let bob = remotePeer("Bob")
        let answers = AnswerLog()
        let bobCertificate = try certificate(.bob)
        harness.push(.didReceiveCertificate(peer: bob, certificate: [bobCertificate], handler: answers.record("first")), link: 0)
        guard case .didReceiveCertificate(_, _, let appHandler)? = harness.output(count: 1).first else {
            return XCTFail("the app decides the first certificate")
        }
        appHandler(true)
        harness.push(.didReceiveCertificate(peer: bob, certificate: [bobCertificate], handler: answers.record("second")), link: 1)
        waitUntil("answered") { answers.values["second"] != nil }
        XCTAssertEqual(answers.values["second"], true)
        harness.assertNoMoreOutput()
    }

    func testSecondLinkForAConnectedPeerIsAdmittedWithoutAsking() {
        let harness = SessionHarness()
        let bob = remotePeer("Bob")
        let answers = AnswerLog()
        harness.push(.devicesChanged(peer: bob.with(.connected), connectedPeers: []), link: 0)
        _ = harness.output(count: 1)
        harness.push(.didReceiveInvitation(peer: bob, context: nil, handler: answers.record("second link")), link: 1)
        waitUntil("answered") { answers.values["second link"] != nil }
        XCTAssertEqual(answers.values["second link"], true)
        harness.assertNoMoreOutput()
    }

    func testOnlyTheSameCertificateIsAcceptedOnASecondLink() throws {
        let harness = SessionHarness()
        let bob = remotePeer("Bob")
        let answers = AnswerLog()
        let bobCertificate = try certificate(.bob)
        let malloryCertificate = try certificate(.mallory)

        harness.push(.didReceiveCertificate(peer: bob, certificate: [bobCertificate], handler: answers.record("first")), link: 0)
        guard case .didReceiveCertificate(_, _, let appHandler)? = harness.output(count: 1).first else {
            return XCTFail("the app decides the first certificate")
        }
        appHandler(true)
        harness.push(.devicesChanged(peer: bob.with(.connected), connectedPeers: []), link: 0)
        _ = harness.output(count: 1)

        harness.push(.didReceiveCertificate(peer: bob, certificate: [bobCertificate], handler: answers.record("same")), link: 1)
        waitUntil("same certificate accepted") { answers.values["same"] != nil }
        XCTAssertEqual(answers.values["same"], true)
        harness.assertNoMoreOutput()

        harness.push(.didReceiveCertificate(peer: bob, certificate: [malloryCertificate], handler: answers.record("other")), link: 1)
        guard case .didReceiveCertificate(_, let presented, _)? = harness.output(count: 1).first else {
            return XCTFail("a different certificate goes to the app")
        }
        XCTAssertEqual(SecCertificateCopyData(presented?.first as! SecCertificate) as Data,
            try PeerNetworkCertificateFixtures.certificateData(.mallory))
        XCTAssertNil(answers.values["other"], "not answered on the app's behalf")
    }

    func testSendsPreferTheFirstLinkAndFallBackWhenItFails() {
        let harness = SessionHarness()
        let bob = remotePeer("Bob")
        harness.links.forEach { $0.connected = [bob] }
        harness.links[0].failSends = true

        let sent = expectation(description: "send completes")
        harness.session.sendData(Data("hi".utf8), toPeers: [bob]) { failures in
            XCTAssertTrue(failures.isEmpty, "delivered over the second link")
            sent.fulfill()
        }
        wait(for: [sent], timeout: 2)
        XCTAssertEqual(harness.links.map { $0.sends }, [1, 1])

        harness.links[1].failSends = true
        let failed = expectation(description: "send fails on every link")
        harness.session.sendData(Data("hi".utf8), toPeers: [bob]) { failures in
            XCTAssertEqual(failures.count, 1)
            failed.fulfill()
        }
        wait(for: [failed], timeout: 2)
    }

    func testPeerOnNoLinkFailsAsNotConnected() {
        let harness = SessionHarness()
        let bob = remotePeer("Bob")
        let sent = expectation(description: "send completes")
        harness.session.sendData(Data("hi".utf8), toPeers: [bob]) { failures in
            guard case .peerNotConnected? = failures[bob] as? PeerConnectionError else {
                return XCTFail("expected peerNotConnected, got \(failures)")
            }
            sent.fulfill()
        }
        wait(for: [sent], timeout: 2)
        XCTAssertEqual(harness.links.map { $0.sends }, [0, 0])
    }

    // MARK: - Helpers

    private func makeManager(_ name: String,
        links radios: [SimulatedBluetoothRadio],
        connectionType: PeerConnectionType = .automatic) -> PeerConnectionManager {
        let security = PeerConnectionNetworkSecurity.preSharedKey(Data("group key".utf8))
        let manager = PeerConnectionManager(serviceType: "combined-test",
            connectionType: connectionType,
            displayName: name,
            networkSecurity: security,
            transportFactory: .combined(radios.map { .bluetooth(security: security, radio: $0.radio) },
                backend: .networkFrameworkAndBluetooth))
        managers.append(manager)
        return manager
    }

    private func remotePeer(_ name: String) -> Peer {
        return Peer(identity: PeerIdentity(identifier: UUID().uuidString, displayName: name), status: .notConnected)
    }

    private func certificate(_ name: PeerNetworkCertificateFixtures.Name) throws -> SecCertificate {
        return try XCTUnwrap(SecCertificateCreateWithData(nil, try PeerNetworkCertificateFixtures.certificateData(name) as CFData))
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout)
    }

    /// Lets asynchronous events finish arriving before asserting that nothing else happened.
    private func settle() {
        let settled = expectation(description: "settled")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
    }
}

/// Counts the app-visible discovery and connection events of one manager.
private final class EventLog {
    private let lock = NSLock()
    private var counts : [String:Int] = [:]

    var found : Int { return count("found") }
    var connections : Int { return count("connected") }
    var disconnections : Int { return count("disconnected") }

    init(_ manager: PeerConnectionManager) {
        manager.listenOn({ [weak self] event in
            switch event {
            case .foundPeer: self?.increment("found")
            case .devicesChanged(let peer, _) where peer.status == .connected: self?.increment("connected")
            case .devicesChanged(let peer, _) where peer.status == .notConnected: self?.increment("disconnected")
            default: break
            }
        }, withKey: "event-log")
    }

    private func increment(_ key: String) {
        lock.lock(); counts[key, default: 0] += 1; lock.unlock()
    }

    private func count(_ key: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[key] ?? 0
    }
}

private final class AnswerLog {
    private let lock = NSLock()
    private var stored : [String:Bool] = [:]

    var values : [String:Bool] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func record(_ name: String) -> (Bool) -> Void {
        return { [weak self] accept in
            self?.lock.lock()
            self?.stored[name] = accept
            self?.lock.unlock()
        }
    }
}

private extension Peer {
    func with(_ status: Peer.Status) -> Peer {
        return Peer(identity: identity, status: status)
    }
}

/// A combined session over two fake links whose events and send results the test controls.
@available(iOS 13.0, macOS 10.15, *)
private final class SessionHarness {

    final class FakeLink : PeerSessionTransport {
        let peer = Peer(identity: PeerIdentity(identifier: UUID().uuidString, displayName: "Alice"), status: .currentUser)
        var observer : Observable<PeerSessionEvent>?
        var connected : [Peer] = []
        var failSends = false
        var sends = 0
        var connectedPeers : [Peer] { return connected }

        func startSession() {}
        func stopSession() {}
        func sendData(_ data: Data, toPeers peers: [Peer]) {}

        func sendData(_ data: Data, toPeers peers: [Peer], completion: @escaping ([Peer:Error]) -> Void) {
            sends += 1
            completion(failSends ? Dictionary(uniqueKeysWithValues: peers.map { ($0, POSIXError(.ENOTCONN) as Error) }) : [:])
        }

        func sendDataStream(_ streamName: String, toPeer peer: Peer) throws -> OutputStream {
            throw POSIXError(.ENOTSUP)
        }

        func sendResourceAtURL(_ resourceURL: URL, withName name: String, toPeer peer: Peer,
            withCompletionHandler completion: ((Error?) -> Void)?) -> Progress? {
            return nil
        }
    }

    let links = [FakeLink(), FakeLink()]
    let session : CombinedPeerSessionTransport
    private let output = Observable<PeerSessionEvent>(.none)
    private let lock = NSLock()
    private var received : [PeerSessionEvent] = []

    init() {
        let links = self.links
        session = CombinedPeerSessionTransport(peer: links[0].peer, observer: output, makeLinks: links.map { link in
            return { observer in
                link.observer = observer
                return link
            }
        })
        output.addObserver({ [weak self] event in
            if case .none = event { return }
            self?.lock.lock()
            self?.received.append(event)
            self?.lock.unlock()
        }, key: "harness", replayCurrentValue: false)
    }

    func push(_ event: PeerSessionEvent, link: Int) {
        links[link].observer?.update(event)
    }

    /// Waits for `count` more output events and returns them.
    func output(count: Int, timeout: TimeInterval = 2) -> [PeerSessionEvent] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            if received.count >= count {
                let events = Array(received.prefix(count))
                received.removeFirst(count)
                lock.unlock()
                return events
            }
            lock.unlock()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("expected \(count) output events")
        return []
    }

    func assertNoMoreOutput(file: StaticString = #filePath, line: UInt = #line) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        lock.lock()
        XCTAssertTrue(received.isEmpty, "unexpected output \(received)", file: file, line: line)
        lock.unlock()
    }
}
