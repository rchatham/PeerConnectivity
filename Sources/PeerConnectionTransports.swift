//
//  PeerConnectionTransports.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal protocol PeerSessionTransport {
    var peer : Peer { get }
    var connectedPeers : [Peer] { get }
    var multipeerSession : MCSession { get }

    func startSession()
    func stopSession()
    func sendData(_ data: Data, toPeers peers: [Peer])
    func sendDataStream(_ streamName: String, toPeer peer: Peer) throws -> OutputStream
    func sendResourceAtURL(_ resourceURL: URL,
        withName name: String,
        toPeer peer: Peer,
        withCompletionHandler completion: ((Error?)->Void)?) -> Progress?
    func nearbyConnectionDataForPeer(_ peer: Peer, withCompletionHandler completion: @escaping (Data?, Error?)->Void)
    func connectPeer(_ peer: Peer, withNearbyConnectionData data: Data)
    func cancelConnectPeer(_ peer: Peer)
}

internal protocol PeerBrowserTransport {
    func invitePeer(_ peer: Peer, withContext context: Data?, timeout: TimeInterval)
    func startBrowsing()
    func stopBrowsing()
}

extension PeerBrowserTransport {
    internal func invitePeer(_ peer: Peer, withContext context: Data? = nil, timeout: TimeInterval = 30) {
        invitePeer(peer, withContext: context, timeout: timeout)
    }
}

internal protocol PeerAdvertiserTransport {
    func startAdvertising()
    func stopAdvertising()
}

internal protocol PeerAdvertiserAssisstantTransport {
    func startAdvertisingAssisstant()
    func stopAdvertisingAssisstant()
}

internal struct PeerConnectionTransportFactory {
    internal let makeSession : (Peer, PeerSecurityConfiguration, Observable<PeerSessionEvent>) -> PeerSessionTransport
    internal let makeBrowser : (PeerSessionTransport, ServiceType, Observable<PeerBrowserEvent>) -> PeerBrowserTransport
    internal let makeAdvertiser : (PeerSessionTransport, ServiceType, PeerDiscoveryInfo?, Observable<PeerAdvertiserEvent>) -> PeerAdvertiserTransport
    internal let makeAdvertiserAssisstant : (PeerSessionTransport, ServiceType, PeerDiscoveryInfo?, Observable<PeerAdvertiserAssisstantEvent>) -> PeerAdvertiserAssisstantTransport

    internal static let multipeerConnectivity = PeerConnectionTransportFactory(
        makeSession: { peer, securityConfiguration, observer in
            let eventProducer = PeerSessionEventProducer(observer: observer)
            return PeerSession(peer: peer,
                               securityConfiguration: securityConfiguration,
                               eventProducer: eventProducer)
        },
        makeBrowser: { session, serviceType, observer in
            let eventProducer = PeerBrowserEventProducer(observer: observer)
            return PeerBrowser(session: session, serviceType: serviceType, eventProducer: eventProducer)
        },
        makeAdvertiser: { session, serviceType, discoveryInfo, observer in
            let eventProducer = PeerAdvertiserEventProducer(observer: observer)
            return PeerAdvertiser(session: session,
                                  serviceType: serviceType,
                                  discoveryInfo: discoveryInfo,
                                  eventProducer: eventProducer)
        },
        makeAdvertiserAssisstant: { session, serviceType, discoveryInfo, observer in
            let eventProducer = PeerAdvertiserAssisstantEventProducer(observer: observer)
            return PeerAdvertiserAssisstant(session: session,
                                            serviceType: serviceType,
                                            discoveryInfo: discoveryInfo,
                                            eventProducer: eventProducer)
        }
    )
}
