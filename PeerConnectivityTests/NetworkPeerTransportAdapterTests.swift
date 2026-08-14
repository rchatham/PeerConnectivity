//
//  NetworkPeerTransportAdapterTests.swift
//  PeerConnectivityTests
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import XCTest
import Network
@testable import PeerConnectivity

@available(iOS 13.0, macOS 10.15, *)
private final class MockNetworkPeerListener : NetworkPeerListening {
    internal var startCallCount = 0
    internal var cancelCallCount = 0

    internal func start() {
        startCallCount += 1
    }

    internal func cancel() {
        cancelCallCount += 1
    }
}

@available(iOS 13.0, macOS 10.15, *)
private final class MockNetworkPeerBrowser : NetworkPeerBrowsing {
    internal var startCallCount = 0
    internal var cancelCallCount = 0

    internal func start() {
        startCallCount += 1
    }

    internal func cancel() {
        cancelCallCount += 1
    }
}

final class NetworkPeerTransportAdapterTests : XCTestCase {

    internal func testNetworkFactoryBuildsInternalTransportsWhenAvailable() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let peer = Peer(displayName: "Local")
        let sessionObserver = Observable<PeerSessionEvent>(.none)
        let browserObserver = Observable<PeerBrowserEvent>(.none)
        let advertiserObserver = Observable<PeerAdvertiserEvent>(.none)
        let assistantObserver = Observable<PeerAdvertiserAssisstantEvent>(.none)
        let session = PeerConnectionTransportFactory.networkFramework.makeSession(peer, .default, sessionObserver)
        let browser = PeerConnectionTransportFactory.networkFramework.makeBrowser(session, "test-service", browserObserver)
        let advertiser = PeerConnectionTransportFactory.networkFramework.makeAdvertiser(session, "test-service", nil, advertiserObserver)
        let assistant = PeerConnectionTransportFactory.networkFramework.makeAdvertiserAssisstant(session, "test-service", nil, assistantObserver)

        XCTAssertTrue(session is NetworkPeerSessionTransport)
        XCTAssertTrue(browser is NetworkPeerBrowserTransport)
        XCTAssertTrue(advertiser is NetworkPeerAdvertiserTransport)
        XCTAssertTrue(assistant is NetworkPeerAdvertiserAssisstantTransport)
    }

    internal func testSessionTransportStartStopDelegatesToListener() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let listener = MockNetworkPeerListener()
        let session = makeSessionTransport(listener: listener)

        session.startSession()
        session.stopSession()

        XCTAssertEqual(listener.startCallCount, 1)
        XCTAssertEqual(listener.cancelCallCount, 1)
    }

    internal func testBrowserTransportStartStopDelegatesToBrowserAndClearsDiscoveredEndpoints() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let browser = MockNetworkPeerBrowser()
        let observer = Observable<PeerBrowserEvent>(.none)
        let transport = NetworkPeerBrowserTransport(session: makeSessionTransport(),
            browser: browser,
            browserObserver: observer)
        let endpoint = NWEndpoint.hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: 12345)
        let identity = PeerIdentity(identifier: "remote", displayName: "Remote")

        transport.foundEndpoint(endpoint, identity: identity)
        transport.startBrowsing()
        transport.stopBrowsing()

        XCTAssertEqual(browser.startCallCount, 1)
        XCTAssertEqual(browser.cancelCallCount, 1)
    }

    internal func testBrowserTransportFoundAndLostEndpointEmitsPeerEvents() async {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let observer = Observable<PeerBrowserEvent>(.none)
        let transport = NetworkPeerBrowserTransport(session: makeSessionTransport(),
            browser: MockNetworkPeerBrowser(),
            browserObserver: observer)
        let endpoint = NWEndpoint.hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: 23456)
        let identity = PeerIdentity(identifier: "remote", displayName: "Remote")
        let foundExpectation = expectation(description: "Found peer emitted")
        let lostExpectation = expectation(description: "Lost peer emitted")
        var events : [PeerBrowserEvent] = []
        await observer.addObserverAsync { event in
            events.append(event)
            switch event {
            case .foundPeer:
                foundExpectation.fulfill()
            case .lostPeer:
                lostExpectation.fulfill()
            default: break
            }
        }

        transport.foundEndpoint(endpoint, identity: identity)
        transport.lostEndpoint(endpoint, identity: identity)
        await fulfillment(of: [foundExpectation, lostExpectation], timeout: 1)

        let foundEvents = events.compactMap { event -> (Peer, PeerDiscoveryInfo?)? in
            guard case .foundPeer(let peer, let discoveryInfo) = event else { return nil }
            return (peer, discoveryInfo)
        }
        let lostPeers = events.compactMap { event -> Peer? in
            guard case .lostPeer(let peer) = event else { return nil }
            return peer
        }
        XCTAssertEqual(foundEvents.first?.0.identity, lostPeers.first?.identity)
        XCTAssertEqual(foundEvents.first?.0.displayName, "Remote")
        XCTAssertNil(foundEvents.first?.1,
            "Network discovery must report nil until app-provided discoveryInfo is supported")
    }

    internal func testBrowserTransportIgnoresSelfEndpoint() async {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let observer = Observable<PeerBrowserEvent>(.none)
        let session = makeSessionTransport()
        let transport = NetworkPeerBrowserTransport(session: session,
            browser: MockNetworkPeerBrowser(),
            browserObserver: observer)
        let endpoint = NWEndpoint.hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: 34567)
        var events : [PeerBrowserEvent] = []
        await observer.addObserverAsync { event in events.append(event) }

        transport.foundEndpoint(endpoint, identity: session.peer.identity)

        XCTAssertEqual(events.count, 1)
    }

    internal func testBrowserTransportIgnoresTruncatedSelfDiscoveryIdentity() async {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let localIdentity = PeerIdentity(identifier: String(repeating: "a", count: 400),
            displayName: "Local")
        let session = makeSessionTransport(peer: Peer(identity: localIdentity, status: .currentUser))
        let observer = Observable<PeerBrowserEvent>(.none)
        let transport = NetworkPeerBrowserTransport(session: session,
            browser: MockNetworkPeerBrowser(),
            browserObserver: observer)
        let endpoint = NWEndpoint.hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: 34568)
        let advertisedIdentity = PeerNetworkDiscoveryInfo(identity: localIdentity).identity
        var events : [PeerBrowserEvent] = []
        await observer.addObserverAsync { event in events.append(event) }

        transport.foundEndpoint(endpoint, identity: advertisedIdentity)
        transport.lostEndpoint(endpoint, identity: advertisedIdentity)

        XCTAssertEqual(events.count, 1)
    }

    internal func testAdvertiserTransportStartStopIsSafeNoOpBecauseSessionOwnsListener() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let listener = MockNetworkPeerListener()
        let session = makeSessionTransport(listener: listener)
        let advertiser = NetworkPeerAdvertiserTransport(session: session,
            serviceType: "test-service",
            advertiserObserver: Observable<PeerAdvertiserEvent>(.none),
            configureListener: false)

        advertiser.startAdvertising()
        advertiser.stopAdvertising()

        XCTAssertEqual(listener.startCallCount, 0)
        XCTAssertEqual(listener.cancelCallCount, 0)
    }

    internal func testUnsupportedNetworkStreamThrows() throws {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let session = makeSessionTransport()

        XCTAssertThrowsError(try session.sendDataStream("stream", toPeer: session.peer))
    }

    internal func testUnsupportedNetworkResourceCompletesWithError() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let session = makeSessionTransport()
        var completionError : Error?
        let progress = session.sendResourceAtURL(URL(fileURLWithPath: "/tmp/missing"),
            withName: "missing",
            toPeer: session.peer,
            withCompletionHandler: { error in completionError = error })

        XCTAssertNil(progress)
        XCTAssertNotNil(completionError)
    }

    @available(iOS 13.0, macOS 10.15, *)
    private func makeSessionTransport(peer: Peer = Peer(displayName: "Local"),
        listener: NetworkPeerListening = MockNetworkPeerListener()) -> NetworkPeerSessionTransport {
        let coordinator = NetworkPeerCoordinator<NetworkPeerConnection>(localPeer: peer,
            sessionObserver: Observable<PeerSessionEvent>(.none))
        return NetworkPeerSessionTransport(peer: peer, coordinator: coordinator, listener: listener)
    }
}
