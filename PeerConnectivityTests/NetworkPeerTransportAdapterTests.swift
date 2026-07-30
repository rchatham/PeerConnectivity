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
        let session = PeerConnectionTransportFactory.networkFramework.makeSession(peer, sessionObserver)
        let browser = PeerConnectionTransportFactory.networkFramework.makeBrowser(session, "test-service", browserObserver)
        let advertiser = PeerConnectionTransportFactory.networkFramework.makeAdvertiser(session, "test-service", advertiserObserver)
        let assistant = PeerConnectionTransportFactory.networkFramework.makeAdvertiserAssisstant(session, "test-service", assistantObserver)

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

        transport.foundEndpoint(endpoint)
        transport.startBrowsing()
        transport.stopBrowsing()

        XCTAssertEqual(browser.startCallCount, 1)
        XCTAssertEqual(browser.cancelCallCount, 1)
    }

    internal func testBrowserTransportFoundAndLostEndpointEmitsPeerEvents() {
        guard #available(iOS 13.0, macOS 10.15, *) else { return }

        let observer = Observable<PeerBrowserEvent>(.none)
        let transport = NetworkPeerBrowserTransport(session: makeSessionTransport(),
            browser: MockNetworkPeerBrowser(),
            browserObserver: observer)
        let endpoint = NWEndpoint.hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: 23456)
        var events : [PeerBrowserEvent] = []
        observer.addObserver { event in
            events.append(event)
        }

        transport.foundEndpoint(endpoint)
        transport.lostEndpoint(endpoint)

        XCTAssertEqual(events.count, 3)
        guard case .foundPeer(let foundPeer) = events[1] else {
            XCTFail("Expected found peer event")
            return
        }
        guard case .lostPeer(let lostPeer) = events[2] else {
            XCTFail("Expected lost peer event")
            return
        }
        XCTAssertEqual(foundPeer.identity, lostPeer.identity)
        XCTAssertEqual(foundPeer.displayName, endpoint.debugDescription)
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
    private func makeSessionTransport(listener: NetworkPeerListening = MockNetworkPeerListener()) -> NetworkPeerSessionTransport {
        let peer = Peer(displayName: "Local")
        let coordinator = NetworkPeerCoordinator<NetworkPeerConnection>(localPeer: peer,
            sessionObserver: Observable<PeerSessionEvent>(.none),
            browserObserver: Observable<PeerBrowserEvent>(.none),
            advertiserObserver: Observable<PeerAdvertiserEvent>(.none))
        return NetworkPeerSessionTransport(peer: peer, coordinator: coordinator, listener: listener)
    }
}
