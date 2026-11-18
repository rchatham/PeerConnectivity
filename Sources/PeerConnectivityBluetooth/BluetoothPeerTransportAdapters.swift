//
//  BluetoothPeerTransportAdapters.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import PeerConnectivity

/// The Bluetooth session: the shared coordinator over `BluetoothPeerConnection`s, plus the
/// peripheral role that accepts inbound channels (the Network backend's listener).
@available(iOS 13.0, macOS 10.15, *)
internal final class BluetoothPeerSessionTransport : PeerSessionTransport {

    internal let peer : Peer
    internal let coordinator : NetworkPeerCoordinator<BluetoothPeerConnection>
    fileprivate let security : PeerConnectionNetworkSecurity
    fileprivate let radio : BluetoothPeerRadio
    fileprivate var advertising : BluetoothPeerAdvertising = FailedBluetoothPeerAdvertising()

    internal var connectedPeers : [Peer] {
        return coordinator.connectedPeers
    }

    internal init(peer: Peer,
        sessionObserver: Observable<PeerSessionEvent>,
        security: PeerConnectionNetworkSecurity,
        radio: BluetoothPeerRadio) {
        self.peer = peer
        var requiresCertificateDecision = false
        if case .certificate = security {
            // The channel only proves key possession; trust is the app's certificate policy.
            requiresCertificateDecision = true
        }
        self.coordinator = NetworkPeerCoordinator<BluetoothPeerConnection>(localPeer: peer,
            sessionObserver: sessionObserver,
            requiresCertificateDecision: requiresCertificateDecision)
        self.security = security
        self.radio = radio
    }

    internal func configureAdvertising(serviceType: ServiceType,
        discoveryInfo: PeerDiscoveryInfo?,
        advertiserObserver: Observable<PeerAdvertiserEvent>) {
        let failed : (PeerConnectionError) -> Void = { error in
            advertiserObserver.update(.didNotStartAdvertisingPeer(error))
        }
        // Fail closed rather than advertise an identity that silently drops caller metadata.
        let appInfo = discoveryInfo ?? [:]
        guard PeerNetworkDiscoveryInfo.isValidAppInfo(appInfo),
            let payload = BluetoothPeerService.identityPayload(for: PeerNetworkDiscoveryInfo(identity: peer.identity,
                appInfo: appInfo)) else {
            advertising = FailedBluetoothPeerAdvertising(error: .invalidDiscoveryInfo, failed: failed)
            return
        }
        advertising = radio.makeAdvertising(serviceType, payload, BluetoothPeerAdvertisingHandlers(
            channelOpened: { [weak self] streams in
                self?.addChannel(streams, direction: .inbound)
            },
            failed: failed))
    }

    internal func startSession() {
        advertising.start()
    }

    internal func stopSession() {
        advertising.cancel()
        coordinator.cancelAllConnections()
    }

    internal func setAdvertising(_ isAdvertising: Bool) {
        advertising.setAdvertising(isAdvertising)
    }

    internal func sendData(_ data: Data, toPeers peers: [Peer] = []) {
        coordinator.sendData(data, toPeers: peers)
    }

    internal func sendData(_ data: Data, toPeers peers: [Peer], completion: @escaping ([Peer:Error]) -> Void) {
        coordinator.sendData(data, toPeers: peers, completion: completion)
    }

    internal func sendDataStream(_ streamName: String, toPeer peer: Peer) throws -> OutputStream {
        throw NSError(domain: "PeerConnectivity.BluetoothPeerSessionTransport", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Bluetooth transport does not support data streams yet.",
        ])
    }

    internal func sendResourceAtURL(_ resourceURL: URL,
        withName name: String,
        toPeer peer: Peer,
        withCompletionHandler completion: ((Error?)->Void)?) -> Progress? {
        completion?(NSError(domain: "PeerConnectivity.BluetoothPeerSessionTransport", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Bluetooth transport does not support resource transfer yet.",
        ]))
        return nil
    }

    /// Hands an open channel to the coordinator. Outbound channels carry the invitation.
    internal func addChannel(_ streams: BluetoothChannelStreams,
        direction: NetworkPeerConnectionDirection,
        invitation: PeerNetworkInvitation? = nil) {
        let connection = BluetoothPeerConnection(inputStream: streams.inputStream,
            outputStream: streams.outputStream,
            direction: direction,
            security: security,
            owner: streams.owner)
        coordinator.addPendingConnection(connection, direction: direction, invitation: invitation)
        connection.start(onFrame: { [weak coordinator, weak connection] frame in
            guard let connection = connection else { return }
            coordinator?.receiveFrame(frame, from: connection)
        }, onClose: { [weak coordinator, weak connection] in
            guard let connection = connection else { return }
            coordinator?.removeConnection(connection)
        })
    }
}

/// Discovery over the central role. BLE has no "gone" callback, so a peer is lost once no
/// advertisement has been seen for `lostPeerTimeout`, the stand-in for Bonjour's removal event.
@available(iOS 13.0, macOS 10.15, *)
internal final class BluetoothPeerBrowserTransport : PeerBrowserTransport {

    fileprivate struct Sighting {
        var peripheral : UUID
        var lastSeen : Date
    }

    fileprivate let session : BluetoothPeerSessionTransport
    fileprivate let browserObserver : Observable<PeerBrowserEvent>
    fileprivate let lostPeerTimeout : TimeInterval
    fileprivate let maxDiscoveredPeers : Int
    fileprivate let now : () -> Date
    fileprivate let lock = NSLock()
    fileprivate var sightings : [PeerIdentity:Sighting] = [:]
    fileprivate var invitations : [UUID:PeerNetworkInvitation] = [:]
    fileprivate var scanner : BluetoothPeerScanning?
    fileprivate var expiryTimer : DispatchSourceTimer?

    internal init(session: BluetoothPeerSessionTransport,
        serviceType: ServiceType,
        browserObserver: Observable<PeerBrowserEvent>,
        radio: BluetoothPeerRadio,
        lostPeerTimeout: TimeInterval,
        maxDiscoveredPeers: Int = NetworkPeerConnectionPolicy().maxDiscoveredPeers,
        now: @escaping () -> Date = Date.init) {
        self.session = session
        self.browserObserver = browserObserver
        self.lostPeerTimeout = lostPeerTimeout
        self.maxDiscoveredPeers = maxDiscoveredPeers
        self.now = now
        self.scanner = radio.makeScanning(serviceType, BluetoothPeerScanningHandlers(
            sighted: { [weak self] peripheral, info in self?.sighted(info, on: peripheral) },
            channelOpened: { [weak self] peripheral, streams in self?.channelOpened(streams, to: peripheral) },
            channelFailed: { [weak self] peripheral, error in self?.channelFailed(to: peripheral, error: error) },
            failed: { error in browserObserver.update(.didNotStartBrowsingForPeers(error)) }))
    }

    deinit {
        expiryTimer?.cancel()
    }

    internal func startBrowsing() {
        scanner?.start()
        startExpiryTimer()
    }

    internal func stopBrowsing() {
        scanner?.cancel()
        lock.lock()
        expiryTimer?.cancel()
        expiryTimer = nil
        sightings.removeAll()
        invitations.removeAll()
        lock.unlock()
    }

    internal func invitePeer(_ peer: Peer, withContext context: Data? = nil, timeout: TimeInterval = 30) {
        lock.lock()
        let peripheral = sightings[peer.identity]?.peripheral
        if let peripheral = peripheral {
            invitations[peripheral] = PeerNetworkInvitation(context: context, timeout: timeout)
        }
        lock.unlock()
        guard let target = peripheral else { return }
        scanner?.openChannel(to: target)
    }

    /// Records a sighting; reports the peer the first time it is seen since it was last lost.
    internal func sighted(_ info: PeerNetworkDiscoveryInfo, on peripheral: UUID) {
        let identity = info.identity
        guard Peer.isValidDisplayName(identity.displayName), !isLocalIdentity(identity) else { return }
        lock.lock()
        let isNew = sightings[identity] == nil
        let isAdmitted = !isNew || sightings.count < maxDiscoveredPeers
        if isAdmitted {
            // A peer's peripheral identifier changes when its address rotates; keep the newest.
            sightings[identity] = Sighting(peripheral: peripheral, lastSeen: now())
        }
        lock.unlock()
        guard isNew, isAdmitted else { return }
        browserObserver.update(.foundPeer(Peer(identity: identity, status: .notConnected),
            discoveryInfo: info.appInfo.isEmpty ? nil : info.appInfo))
    }

    /// Reports every peer not seen within `lostPeerTimeout`. Connected peers are included:
    /// `.lostPeer` describes discovery, as on the Network backend, and a dropped connection
    /// is reported by its stream closing.
    internal func expireSightings() {
        let cutoff = now().addingTimeInterval(-lostPeerTimeout)
        lock.lock()
        let lost = sightings.filter { $0.value.lastSeen < cutoff }.map { $0.key }
        lost.forEach { sightings.removeValue(forKey: $0) }
        lock.unlock()
        lost.forEach { browserObserver.update(.lostPeer(Peer(identity: $0, status: .notConnected))) }
    }

    fileprivate func channelOpened(_ streams: BluetoothChannelStreams, to peripheral: UUID) {
        lock.lock()
        let invitation = invitations.removeValue(forKey: peripheral)
        lock.unlock()
        // Channels are only opened for invitations; anything else is released, which closes it.
        guard let pendingInvitation = invitation else { return }
        session.addChannel(streams, direction: .outbound, invitation: pendingInvitation)
    }

    fileprivate func channelFailed(to peripheral: UUID, error: Error?) {
        lock.lock()
        invitations.removeValue(forKey: peripheral)
        lock.unlock()
        NSLog("%@", "PeerConnectivity: Bluetooth channel failed: \(error.map { "\($0)" } ?? "peer unavailable")")
    }

    /// Checks at a quarter of the timeout (at most once a second), so a peer is reported lost
    /// within a quarter of the timeout after it expires.
    fileprivate func startExpiryTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "PeerConnectivity.BluetoothPeerBrowserTransport"))
        let interval = min(1, lostPeerTimeout / 4)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.expireSightings() }
        lock.lock()
        expiryTimer?.cancel()
        expiryTimer = timer
        lock.unlock()
        timer.resume()
    }

    fileprivate func isLocalIdentity(_ identity: PeerIdentity) -> Bool {
        let advertisedIdentity = PeerNetworkDiscoveryInfo(identity: session.peer.identity).identity
        return identity == session.peer.identity || identity == advertisedIdentity
    }
}

@available(iOS 13.0, macOS 10.15, *)
internal final class BluetoothPeerAdvertiserTransport : PeerAdvertiserTransport {

    fileprivate let session : BluetoothPeerSessionTransport

    internal init(session: BluetoothPeerSessionTransport,
        serviceType: ServiceType,
        discoveryInfo: PeerDiscoveryInfo?,
        advertiserObserver: Observable<PeerAdvertiserEvent>) {
        self.session = session
        session.configureAdvertising(serviceType: serviceType,
            discoveryInfo: discoveryInfo,
            advertiserObserver: advertiserObserver)
    }

    internal func startAdvertising() {
        session.setAdvertising(true)
    }

    internal func stopAdvertising() {
        session.setAdvertising(false)
    }
}

internal final class BluetoothPeerAdvertiserAssisstantTransport : PeerAdvertiserAssisstantTransport {

    internal init() {}

    internal func startAdvertisingAssisstant() {}

    internal func stopAdvertisingAssisstant() {}
}

@available(iOS 13.0, macOS 10.15, *)
extension PeerConnectionTransportFactory {

    /// - parameter browserCreated: Lets tests drive expiry on the browser the manager builds.
    internal static func bluetooth(security: PeerConnectionNetworkSecurity,
        lostPeerTimeout: TimeInterval = 5,
        radio: BluetoothPeerRadio = .coreBluetooth,
        now: @escaping () -> Date = Date.init,
        browserCreated: ((BluetoothPeerBrowserTransport) -> Void)? = nil) -> PeerConnectionTransportFactory {
        validate(security)
        precondition(lostPeerTimeout > 0, "PeerConnectivity: Bluetooth lostPeerTimeout must be positive")
        return PeerConnectionTransportFactory(
            backend: .bluetooth,
            makeSession: { peer, _, observer in
                return BluetoothPeerSessionTransport(peer: peer, sessionObserver: observer, security: security, radio: radio)
            },
            makeBrowser: { session, serviceType, observer in
                guard let session = session as? BluetoothPeerSessionTransport else {
                    fatalError("PeerConnectivity: Bluetooth browser requires BluetoothPeerSessionTransport")
                }
                let browser = BluetoothPeerBrowserTransport(session: session,
                    serviceType: serviceType,
                    browserObserver: observer,
                    radio: radio,
                    lostPeerTimeout: lostPeerTimeout,
                    now: now)
                browserCreated?(browser)
                return browser
            },
            makeAdvertiser: { session, serviceType, discoveryInfo, observer in
                guard let session = session as? BluetoothPeerSessionTransport else {
                    fatalError("PeerConnectivity: Bluetooth advertiser requires BluetoothPeerSessionTransport")
                }
                return BluetoothPeerAdvertiserTransport(session: session,
                    serviceType: serviceType,
                    discoveryInfo: discoveryInfo,
                    advertiserObserver: observer)
            },
            makeAdvertiserAssisstant: { _, _, _, _ in
                return BluetoothPeerAdvertiserAssisstantTransport()
            })
    }

    /// Traps on an unusable configuration when the manager is created, not later on a Core
    /// Bluetooth callback for each connection.
    fileprivate static func validate(_ security: PeerConnectionNetworkSecurity) {
        switch security {
        case .unauthenticated:
            break
        case .preSharedKey(let key):
            precondition(!key.isEmpty, "PeerConnectivity: Bluetooth pre-shared key must not be empty")
        case .certificate(let identity):
            precondition(BluetoothCertificateCredential(identity: identity) != nil,
                "PeerConnectivity: Bluetooth certificate identity is invalid or uses an unsupported key type")
        }
    }
}
