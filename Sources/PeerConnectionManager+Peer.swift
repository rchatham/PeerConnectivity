//
//  PeerConnectionManager+Peer.swift
//  PeerConnectivity
//
//  Created by Julien Di Marco on 25/10/2018.
//  Copyright © 2018 Reid Chatham. All rights reserved.
//

import Foundation

// MARK: - Peer Manipulation (invitation / transmission) -

public extension PeerConnectionManager {

    @discardableResult
    func peerServiceAvailable(_ peer: Peer) throws -> Bool {
        /// ^ is equal check internal 'MCPeer', here we need to compare instance too
        /// similar to generation trick ^^
        guard foundPeers.contains(where: { $0 == peer && $0 === peer }) else {
            logger.error("peer invitation canceled, peer: \(peer.peerID), error: \(Error.peerUnavailable)")
            throw Error.peerUnavailable
        }

        let matchingConnectedServicePeers = connectedServicePeers.filter {
            return ($0 == peer || $0 === peer || $0.displayName == peer.displayName) && $0.status == .connected
        }

        guard matchingConnectedServicePeers.count <= 0 else {
            logger.error("peer invitation canceled, peer: \(peer.peerID), error: \(Error.serviceAlreadyConnected)")
            throw Error.serviceAlreadyConnected
        }

        return true
    }

    // Use to invite peers that have been found locally to join a MultipeerConnectivity session.
    //
    // - parameter peer: `Peer` object to invite to current session.
    // - parameter withContext: `Data` object associated with the invitation.
    // - parameter timeout: Time interval until the invitation expires.

    func invitePeer(_ peer: Peer, withContext context: Data? = nil, timeout: TimeInterval = 30) throws {
        mutex.lock()
        defer { mutex.unlock() }

        try peerServiceAvailable(peer)
        try browser?.invitePeer(peer, withContext: context, timeout: timeout)
    }

    internal func invitePeer(invitation: Invitation, context: Data? = nil, timeout: TimeInterval = 30) throws {
        mutex.lock()
        defer { mutex.unlock() }

        try peerServiceAvailable(invitation.peer)
        try browser?.invitePeer(invitation: invitation, context: context, timeout: timeout)
    }

    func attemptReconnect(_ peer: Peer, context: Data? = nil, timeout: TimeInterval = 30,
                                 delay: DispatchTimeInterval = .seconds(5)) throws {
        var reconnectWorkItem: DispatchWorkItem? = nil

        mutex.lock()
        defer { mutex.unlock() }

        guard foundPeers.contains(peer) else {
            throw Error.peerUnavailable
        }

        logger.info("AttemptReconnect - peer: \(peer)")
        reconnectWorkItem = DispatchWorkItem { [weak self] in
            guard let strongSelf = self, reconnectWorkItem?.isCancelled == false else {
                return
            }

            try? strongSelf.invitePeer(peer, withContext: context, timeout: timeout)
            reconnectWorkItem = nil
        }

        guard let connectionWorkItem = reconnectWorkItem else {
            return
        }

        let deadline: DispatchTime = .now() + delay
        retyAttemptQueue?.asyncAfter(deadline: deadline, execute: connectionWorkItem)
    }

    /// Send data to connected users. If no peer is specified it broadcasts to all users on a current session.
    ///
    /// - parameter data: Data to be sent to specified peers.
    /// - parameter toPeers: Specified `Peer` objects to send data.
    ///
    ///  Lastests change improve `sending` in `PeerManagerMode.node` managerMode (aka mesh networking mode)
    ///    In the following mode, 'pcm' use both a `master` session and multiple `slave` session
    ///    this allow to create a simili `mesh` network where every one is connected together
    ///
    ///   Previously `sendData` would only use the `master` session and send data to it's `connected` peers
    ///    However, w/ multiple connection/session in `node` mode, some distant `slave` migh have issue connecting
    ///    to our local session, even though they're already connected to another node `master` session
    ///    If we're also connected to that node `master` session, then we also have access to all it's peers
    ///     in the session
    ///
    ///   This latests change utilize such shared access of peers between sessions to maximize the number of peer a
    ///     single node can reach inside of the `mesh` network
    ///
    ///    - First the `sendData` request all user, we compute all available peers from the following data:
    ///      (local `master` session).connectedPeers + (all distant `master` session).connectedPeers + distant node peer
    ///
    ///    - Using this list of `requestedPeers` we filter all the available sessions including any of the `requestedPeers`
    ///
    ///    - finaly, using the match sessions, we iterate on all session, forwarding the provided data
    ///        session by session, matching each session w/ the actual peers that it contains.
    ///         we also continuously substract the `requestedPeers` array, to avoid sending duplicate data
    ///         to the same peer over multiple sessions.
    ///
    ///
    ///     This actually could still be improve, since we will randomly use theses session to reach a single peer
    ///     as mentioned above a peer can be access in multiple session, currently the only optimisation is that we use
    ///     our local session in priority, however it would be possible in the futur to prefer some session for peer
    ///     depending on the context of each service/session and the proximity of the peer.

    func sendData(_ data: Data, toPeers peers: [Peer] = []) {
        var peerRequested = peers.isEmpty == true ? allAvailablePeers : peers
        let sessions: [PeerSession] = allAvailableSessions.reduce([]) { (sessions, serviceSession) in
            let containsServicePeer = peerRequested.contains(serviceSession.servicePeer)
            let connectedPeers = serviceSession.connectedPeers.first(where: { return peerRequested.contains($0) })
            let containsConnectedPeers = connectedPeers != nil

            return sessions + ((containsServicePeer || containsConnectedPeers) ? [serviceSession] : [])
        }

        for session in sessions {
            let peerInSession = session.connectedPeers.filter { peerRequested.contains($0) }
            peerRequested = Array(Set(peerRequested).subtracting(peerInSession))

            guard peerInSession.isEmpty == false else { continue }

            session.sendData(data, toPeers: peerInSession)
            logger.verbose("sendData - on session: \(session), for peers: \(peerInSession), requested: \(peerRequested)")
        }
    }

    // Send events to connected users. Encoded as Data using the NSKeyedArchiver.
    //   If no peer is specified it broadcasts to all users on a current session.
    //
    // - parameter eventInfo: Dictionary of Any data which is encoded with
    //    the NSKeyedArchiver and passed to the specified peers.
    // - parameter toPeers: Specified `Peer` objects to send event.

    func sendEvent(_ eventInfo: [String:Any], toPeers peers: [Peer] = []) {
        let eventData = NSKeyedArchiver.archivedData(withRootObject: eventInfo)
        session.sendData(eventData, toPeers: peers)
    }

    // Send a data stream to a connected user. This method throws an error if the stream cannot be established.
    //    This method returns the NSOutputStream with which you can send events to the connected users.
    //
    // - parameter streamName: The name of the stream to be established between two users.
    // - parameter toPeer: The peer with which to start a data stream
    //
    // - Throws: Propagates errors thrown by Apple's MultipeerConnectivity framework.
    //
    // - Returns: The OutputStream for sending information to the specified `Peer` object.

    func sendDataStream(streamName name: String, toPeer peer: Peer) throws -> OutputStream {
        do { return try session.sendDataStream(name, toPeer: peer) }
        catch let error { throw error }
    }

    // Send a resource with a specified url for retrieval on a connected device.
    //    This method can send a resource to multiple peers and returns an Progress associated with each Peer.
    //    This method takes an error completion handler if the resource fails to send.
    //
    // - parameter resourceURL: The url that the resource will be passed with for retrieval.
    // - parameter withName: The name with which the progress is associated with.
    // - parameter toPeers: The specified peers for the resource to be sent to.
    // - parameter withCompletionHandler: the completion handler called when an error is thrown sending a resource.
    //
    // - Returns: A dictionary of optional Progress associated with each peer that the resource was sent to.

    func sendResourceAtURL(_ resourceURL: URL, withName name: String, toPeers peers: [Peer] = [],
                                  withCompletionHandler completion: ((Swift.Error?) -> Void)? ) -> [Peer:Progress?] {

        var progress: [Peer: Progress?] = [:]
        let peers = (peers.isEmpty) ? self.connectedPeers : peers
        for peer in peers {
            progress[peer] = session.sendResourceAtURL(resourceURL, withName: name, toPeer: peer,
                                                       withCompletionHandler: completion)
        }
        return progress
    }
}
