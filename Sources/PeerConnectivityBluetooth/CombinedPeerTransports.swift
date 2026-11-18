//
//  CombinedPeerTransports.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import Security
import PeerConnectivity

/// Runs several links (Network framework and Bluetooth) under one manager, so the app sees one
/// peer, one connection and one invitation whichever radios carry it.
///
/// Each link keeps its own coordinator and connections. When a peer is reachable over more than
/// one link, every link connects, and the peer counts as connected until its last link drops,
/// so losing Wi-Fi mid-session is not visible to the app. Sends use the most preferred
/// connected link (the first in `links`) and fall back to the next one if a send fails.
@available(iOS 13.0, macOS 10.15, *)
internal final class CombinedPeerSessionTransport : PeerSessionTransport {

    fileprivate struct PendingDecision {
        let startedAt : Date
        let certificate : Data?
        var waiting : [(Bool) -> Void]
    }

    /// The app's answer for a peer, reused by its other links.
    fileprivate struct Answer {
        let accept : Bool
        let answeredAt : Date
        let certificate : Data?
    }

    /// How long an unanswered decision blocks a second prompt, and how long an answer covers
    /// links that connect before the first one is reported connected.
    fileprivate static let decisionTimeout : TimeInterval = 30

    internal let peer : Peer
    /// Most preferred first.
    internal let links : [PeerSessionTransport]
    fileprivate let observer : Observable<PeerSessionEvent>
    fileprivate let linkObservers : [Observable<PeerSessionEvent>]
    fileprivate let lock = NSLock()
    fileprivate var connectedLinks : [PeerIdentity:Set<Int>] = [:]
    fileprivate var invitationAnswers : [PeerIdentity:Answer] = [:]
    /// Accepted certificates only; a rejected one is always asked about again.
    fileprivate var certificateAnswers : [PeerIdentity:Answer] = [:]
    fileprivate var pendingInvitations : [PeerIdentity:PendingDecision] = [:]
    fileprivate var pendingCertificates : [PeerIdentity:PendingDecision] = [:]

    internal var connectedPeers : [Peer] {
        var seen = Set<PeerIdentity>()
        return links.flatMap { $0.connectedPeers }.filter { seen.insert($0.identity).inserted }
    }

    internal init(peer: Peer,
        observer: Observable<PeerSessionEvent>,
        makeLinks: [(Observable<PeerSessionEvent>) -> PeerSessionTransport]) {
        let linkObservers = makeLinks.map { _ in Observable<PeerSessionEvent>(.none) }
        self.peer = peer
        self.observer = observer
        self.linkObservers = linkObservers
        self.links = zip(makeLinks, linkObservers).map { make, linkObserver in make(linkObserver) }
        for (index, linkObserver) in linkObservers.enumerated() {
            linkObserver.addObserver({ [weak self] event in
                self?.handle(event, fromLink: index)
            }, key: "combined", replayCurrentValue: false)
        }
    }

    internal func isConnected(_ peer: Peer, onLink link: Int? = nil) -> Bool {
        guard let link = link else { return links.contains { $0.connectedPeers.contains(peer) } }
        return links[link].connectedPeers.contains(peer)
    }

    internal func startSession() {
        links.forEach { $0.startSession() }
    }

    internal func stopSession() {
        links.forEach { $0.stopSession() }
    }

    internal func sendData(_ data: Data, toPeers peers: [Peer]) {
        sendData(data, toPeers: peers, completion: { _ in })
    }

    internal func sendData(_ data: Data, toPeers peers: [Peer], completion: @escaping ([Peer:Error]) -> Void) {
        send(data, to: peers.isEmpty ? connectedPeers : peers, tried: [:], lastErrors: [:], completion: completion)
    }

    internal func sendDataStream(_ streamName: String, toPeer peer: Peer) throws -> OutputStream {
        throw NSError(domain: "PeerConnectivity.CombinedPeerSessionTransport", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Combined transport does not support data streams yet.",
        ])
    }

    internal func sendResourceAtURL(_ resourceURL: URL,
        withName name: String,
        toPeer peer: Peer,
        withCompletionHandler completion: ((Error?)->Void)?) -> Progress? {
        completion?(NSError(domain: "PeerConnectivity.CombinedPeerSessionTransport", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Combined transport does not support resource transfer yet.",
        ]))
        return nil
    }

    // MARK: Sending

    /// Sends each peer's copy over its most preferred connected link not yet tried. A peer whose
    /// send fails locally (for example, its link closing mid-write) is retried on its next link.
    fileprivate func send(_ data: Data,
        to peers: [Peer],
        tried: [PeerIdentity:Set<Int>],
        lastErrors: [PeerIdentity:Error],
        completion: @escaping ([Peer:Error]) -> Void) {
        var failures : [Peer:Error] = [:]
        var batches : [Int:[Peer]] = [:]
        for peer in peers {
            let untried = links.indices.first { index in
                !(tried[peer.identity]?.contains(index) ?? false) && links[index].connectedPeers.contains(peer)
            }
            guard let link = untried else {
                failures[peer] = lastErrors[peer.identity] ?? PeerConnectionError.peerNotConnected(peer)
                continue
            }
            batches[link, default: []].append(peer)
        }
        guard !batches.isEmpty else {
            completion(failures)
            return
        }

        let group = DispatchGroup()
        let resultsLock = NSLock()
        var retries : [Peer] = []
        var errors = lastErrors
        var nextTried = tried
        for (link, batch) in batches {
            batch.forEach { nextTried[$0.identity, default: []].insert(link) }
            group.enter()
            links[link].sendData(data, toPeers: batch) { linkFailures in
                resultsLock.lock()
                for (failedPeer, error) in linkFailures {
                    retries.append(failedPeer)
                    errors[failedPeer.identity] = error
                }
                resultsLock.unlock()
                group.leave()
            }
        }
        group.notify(queue: DispatchQueue.global()) { [weak self] in
            guard let self = self, !retries.isEmpty else {
                completion(failures)
                return
            }
            self.send(data, to: retries, tried: nextTried, lastErrors: errors) { retryFailures in
                completion(failures.merging(retryFailures) { _, latest in latest })
            }
        }
    }

    // MARK: Merging link events

    fileprivate func handle(_ event: PeerSessionEvent, fromLink link: Int) {
        switch event {
        case .none:
            return
        case .devicesChanged(let changedPeer, _):
            guard linkChangeIsVisible(changedPeer, link: link) else { return }
            observer.update(.devicesChanged(peer: changedPeer, connectedPeers: connectedPeers))
        case .didReceiveInvitation(let invitingPeer, let context, let handler):
            decideInvitation(from: invitingPeer, context: context, handler: handler)
        case .didReceiveCertificate(let certifiedPeer, let certificate, let handler):
            decideCertificate(certificate, from: certifiedPeer, handler: handler)
        default:
            observer.update(event)
        }
    }

    /// Records a link's connection change and reports whether the peer as a whole changed:
    /// connected on its first link, disconnected when its last link drops.
    fileprivate func linkChangeIsVisible(_ changedPeer: Peer, link: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var peerLinks = connectedLinks[changedPeer.identity] ?? []
        let wasConnected = !peerLinks.isEmpty
        switch changedPeer.status {
        case .connected:
            peerLinks.insert(link)
        case .notConnected:
            peerLinks.remove(link)
        case .connecting, .currentUser:
            return !wasConnected
        }
        connectedLinks[changedPeer.identity] = peerLinks.isEmpty ? nil : peerLinks
        if wasConnected && peerLinks.isEmpty {
            // The next connection is a new session; the app decides it afresh.
            invitationAnswers.removeValue(forKey: changedPeer.identity)
            certificateAnswers.removeValue(forKey: changedPeer.identity)
        }
        return wasConnected != !peerLinks.isEmpty
    }

    /// One answer per peer: a second link for a connected peer is admitted without asking, and an
    /// invitation that arrives while the app is answering another one for the same peer, or
    /// shortly after it answered, shares that answer. Identity is self-asserted, so this admits nothing a single link would not:
    /// with a pre-shared key both links prove the key, and with certificates each link still
    /// has to present the certificate the app accepted (see `decideCertificate`).
    fileprivate func decideInvitation(from invitingPeer: Peer, context: Data?, handler: @escaping (Bool) -> Void) {
        let identity = invitingPeer.identity
        lock.lock()
        if connectedLinks[identity] != nil {
            lock.unlock()
            handler(true)
            return
        }
        // Answered for another link that has not reported connected yet.
        if let answer = invitationAnswers[identity], isFresh(answer.answeredAt) {
            lock.unlock()
            handler(answer.accept)
            return
        }
        if var pending = pendingInvitations[identity], isFresh(pending.startedAt) {
            pending.waiting.append(handler)
            pendingInvitations[identity] = pending
            lock.unlock()
            return
        }
        pendingInvitations[identity] = PendingDecision(startedAt: Date(), certificate: nil, waiting: [])
        lock.unlock()
        observer.update(.didReceiveInvitation(peer: invitingPeer, context: context, handler: { [weak self] accept in
            var waiting : [(Bool) -> Void] = []
            if let self = self {
                self.lock.lock()
                self.invitationAnswers[identity] = Answer(accept: accept, answeredAt: Date(), certificate: nil)
                waiting = self.pendingInvitations.removeValue(forKey: identity)?.waiting ?? []
                self.lock.unlock()
            }
            handler(accept)
            waiting.forEach { $0(accept) }
        }))
    }

    /// The app's certificate policy runs once per peer and certificate. Another link presenting
    /// the certificate the app accepted, while the peer is connected or shortly after the
    /// acceptance, is accepted; a different certificate is always put to the app.
    fileprivate func decideCertificate(_ certificate: [Any]?, from certifiedPeer: Peer, handler: @escaping (Bool) -> Void) {
        let identity = certifiedPeer.identity
        let leaf = CombinedPeerSessionTransport.leafData(certificate)
        lock.lock()
        if let leaf = leaf, let answer = certificateAnswers[identity], answer.certificate == leaf,
            connectedLinks[identity] != nil || isFresh(answer.answeredAt) {
            lock.unlock()
            handler(true)
            return
        }
        if let leaf = leaf, var pending = pendingCertificates[identity], pending.certificate == leaf, isFresh(pending.startedAt) {
            pending.waiting.append(handler)
            pendingCertificates[identity] = pending
            lock.unlock()
            return
        }
        pendingCertificates[identity] = PendingDecision(startedAt: Date(), certificate: leaf, waiting: [])
        lock.unlock()
        observer.update(.didReceiveCertificate(peer: certifiedPeer, certificate: certificate, handler: { [weak self] accept in
            guard let self = self else {
                handler(accept)
                return
            }
            self.lock.lock()
            if accept, let leaf = leaf {
                self.certificateAnswers[identity] = Answer(accept: true, answeredAt: Date(), certificate: leaf)
            }
            let waiting = self.pendingCertificates[identity]?.certificate == leaf
                ? (self.pendingCertificates.removeValue(forKey: identity)?.waiting ?? []) : []
            self.lock.unlock()
            handler(accept)
            waiting.forEach { $0(accept) }
        }))
    }

    fileprivate func isFresh(_ date: Date) -> Bool {
        return Date().timeIntervalSince(date) < CombinedPeerSessionTransport.decisionTimeout
    }

    fileprivate static func leafData(_ certificate: [Any]?) -> Data? {
        guard let first = certificate?.first, CFGetTypeID(first as CFTypeRef) == SecCertificateGetTypeID() else { return nil }
        return SecCertificateCopyData(first as! SecCertificate) as Data
    }
}

/// Discovery across links: a peer is found when the first link sees it and lost when the last
/// one does. Invitations go out on every link that sees the peer.
@available(iOS 13.0, macOS 10.15, *)
internal final class CombinedPeerBrowserTransport : PeerBrowserTransport {

    fileprivate let session : CombinedPeerSessionTransport
    fileprivate let browsers : [PeerBrowserTransport]
    fileprivate let linkObservers : [Observable<PeerBrowserEvent>]
    fileprivate let observer : Observable<PeerBrowserEvent>
    fileprivate let lock = NSLock()
    fileprivate var foundLinks : [PeerIdentity:Set<Int>] = [:]
    /// Peers this side invited, with the invitation to repeat on links that find them later.
    fileprivate var invitations : [PeerIdentity:(context: Data?, timeout: TimeInterval)] = [:]

    internal init(session: CombinedPeerSessionTransport,
        observer: Observable<PeerBrowserEvent>,
        makeBrowsers: [(Observable<PeerBrowserEvent>) -> PeerBrowserTransport]) {
        let linkObservers = makeBrowsers.map { _ in Observable<PeerBrowserEvent>(.none) }
        self.session = session
        self.observer = observer
        self.linkObservers = linkObservers
        self.browsers = zip(makeBrowsers, linkObservers).map { make, linkObserver in make(linkObserver) }
        for (index, linkObserver) in linkObservers.enumerated() {
            linkObserver.addObserver({ [weak self] event in
                self?.handle(event, fromLink: index)
            }, key: "combined", replayCurrentValue: false)
        }
    }

    internal func invitePeer(_ peer: Peer, withContext context: Data? = nil, timeout: TimeInterval = 30) {
        lock.lock()
        let links = foundLinks[peer.identity] ?? []
        if !links.isEmpty {
            invitations[peer.identity] = (context, timeout)
        }
        lock.unlock()
        links.sorted().forEach { browsers[$0].invitePeer(peer, withContext: context, timeout: timeout) }
    }

    internal func startBrowsing() {
        browsers.forEach { $0.startBrowsing() }
    }

    internal func stopBrowsing() {
        browsers.forEach { $0.stopBrowsing() }
        lock.lock()
        foundLinks.removeAll()
        invitations.removeAll()
        lock.unlock()
    }

    fileprivate func handle(_ event: PeerBrowserEvent, fromLink link: Int) {
        switch event {
        case .none:
            return
        case .foundPeer(let foundPeer, _):
            lock.lock()
            var peerLinks = foundLinks[foundPeer.identity] ?? []
            let isNewPeer = peerLinks.isEmpty
            let isNewLink = peerLinks.insert(link).inserted
            foundLinks[foundPeer.identity] = peerLinks
            let invitation = isNewLink ? invitations[foundPeer.identity] : nil
            lock.unlock()
            if isNewPeer {
                observer.update(event)
            }
            // A peer this side invited gets every link that finds it, including one that comes
            // back (Wi-Fi turned on again), so it regains its faster path without app action.
            if let invitation = invitation, !session.isConnected(foundPeer, onLink: link) {
                browsers[link].invitePeer(foundPeer, withContext: invitation.context, timeout: invitation.timeout)
            }
        case .lostPeer(let lostPeer):
            lock.lock()
            var peerLinks = foundLinks[lostPeer.identity] ?? []
            let wasTracked = peerLinks.remove(link) != nil
            foundLinks[lostPeer.identity] = peerLinks.isEmpty ? nil : peerLinks
            if peerLinks.isEmpty {
                invitations.removeValue(forKey: lostPeer.identity)
            }
            lock.unlock()
            if wasTracked && peerLinks.isEmpty {
                observer.update(event)
            }
        default:
            observer.update(event)
        }
    }
}

/// Advertises on every link; failures on one link are reported without stopping the others.
@available(iOS 13.0, macOS 10.15, *)
internal final class CombinedPeerAdvertiserTransport : PeerAdvertiserTransport {

    fileprivate let advertisers : [PeerAdvertiserTransport]
    fileprivate let linkObservers : [Observable<PeerAdvertiserEvent>]

    internal init(observer: Observable<PeerAdvertiserEvent>,
        makeAdvertisers: [(Observable<PeerAdvertiserEvent>) -> PeerAdvertiserTransport]) {
        let linkObservers = makeAdvertisers.map { _ in Observable<PeerAdvertiserEvent>(.none) }
        self.linkObservers = linkObservers
        self.advertisers = zip(makeAdvertisers, linkObservers).map { make, linkObserver in make(linkObserver) }
        linkObservers.forEach { linkObserver in
            linkObserver.addObserver({ event in
                if case .none = event { return }
                observer.update(event)
            }, key: "combined", replayCurrentValue: false)
        }
    }

    internal func startAdvertising() {
        advertisers.forEach { $0.startAdvertising() }
    }

    internal func stopAdvertising() {
        advertisers.forEach { $0.stopAdvertising() }
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension PeerConnectionTransportFactory {

    /// Combines link factories, most preferred first, into one transport.
    internal static func combined(_ linkFactories: [PeerConnectionTransportFactory],
        backend: PeerConnectionBackend) -> PeerConnectionTransportFactory {
        precondition(linkFactories.count > 1, "PeerConnectivity: combine at least two links")
        return PeerConnectionTransportFactory(
            backend: backend,
            makeSession: { peer, configuration, observer in
                return CombinedPeerSessionTransport(peer: peer, observer: observer, makeLinks: linkFactories.map { factory in
                    return { linkObserver in factory.makeSession(peer, configuration, linkObserver) }
                })
            },
            makeBrowser: { session, serviceType, observer in
                let combined = combinedSession(session)
                return CombinedPeerBrowserTransport(session: combined, observer: observer,
                    makeBrowsers: zip(linkFactories, combined.links).map { factory, link in
                        return { linkObserver in factory.makeBrowser(link, serviceType, linkObserver) }
                    })
            },
            makeAdvertiser: { session, serviceType, discoveryInfo, observer in
                let combined = combinedSession(session)
                return CombinedPeerAdvertiserTransport(observer: observer,
                    makeAdvertisers: zip(linkFactories, combined.links).map { factory, link in
                        return { linkObserver in factory.makeAdvertiser(link, serviceType, discoveryInfo, linkObserver) }
                    })
            },
            makeAdvertiserAssisstant: { _, _, _, _ in
                // Network and Bluetooth have no advertiser assistant.
                return BluetoothPeerAdvertiserAssisstantTransport()
            })
    }

    fileprivate static func combinedSession(_ session: PeerSessionTransport) -> CombinedPeerSessionTransport {
        guard let combined = session as? CombinedPeerSessionTransport else {
            fatalError("PeerConnectivity: combined transports require CombinedPeerSessionTransport")
        }
        return combined
    }
}
