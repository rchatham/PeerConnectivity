//
//  NetworkPeerTransport.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import Network

@available(iOS 13.0, macOS 10.15, *)
internal final class NetworkPeerConnection : NetworkPeerConnectionCancellable {

    internal typealias StateHandler = (NWConnection.State) -> Void
    internal typealias DataHandler = (PeerNetworkFrame) -> Void
    internal typealias InvalidFrameHandler = () -> Void
    internal typealias HandshakeEncoder = (PeerNetworkHandshake) throws -> Data

    fileprivate let connection : NWConnection
    fileprivate let queue : DispatchQueue
    fileprivate let stateHandler : StateHandler?
    fileprivate let dataHandler : DataHandler?
    fileprivate let invalidFrameHandler : InvalidFrameHandler?
    fileprivate let handshakeEncoder : HandshakeEncoder
    fileprivate var frameDecoder = PeerNetworkFrameDecoder()
    fileprivate var isReceiveTerminal = false

    internal init(endpoint: NWEndpoint,
        queue: DispatchQueue = DispatchQueue(label: "PeerConnectivity.NetworkPeerConnection"),
        stateHandler: StateHandler? = nil,
        dataHandler: DataHandler? = nil,
        invalidFrameHandler: InvalidFrameHandler? = nil,
        handshakeEncoder: @escaping HandshakeEncoder = { try JSONEncoder().encode($0) }) {
        self.connection = NWConnection(to: endpoint, using: NetworkPeerConnection.parameters())
        self.queue = queue
        self.stateHandler = stateHandler
        self.dataHandler = dataHandler
        self.invalidFrameHandler = invalidFrameHandler
        self.handshakeEncoder = handshakeEncoder
    }

    internal init(connection: NWConnection,
        queue: DispatchQueue = DispatchQueue(label: "PeerConnectivity.NetworkPeerConnection"),
        stateHandler: StateHandler? = nil,
        dataHandler: DataHandler? = nil,
        invalidFrameHandler: InvalidFrameHandler? = nil,
        handshakeEncoder: @escaping HandshakeEncoder = { try JSONEncoder().encode($0) }) {
        self.connection = connection
        self.queue = queue
        self.stateHandler = stateHandler
        self.dataHandler = dataHandler
        self.invalidFrameHandler = invalidFrameHandler
        self.handshakeEncoder = handshakeEncoder
    }

    internal func start() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.stateHandler?(state)
            switch state {
            case .ready:
                self?.receiveNextFrame()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    internal func cancel() {
        connection.cancel()
    }

    internal func sendFrame(_ frame: PeerNetworkFrame, completion: ((NWError?) -> Void)? = nil) {
        guard frame.payload.count <= PeerNetworkFrame.maxPayloadLength else {
            completion?(.posix(.EMSGSIZE))
            return
        }

        connection.send(content: frame.encoded(), completion: .contentProcessed { error in
            completion?(error)
        })
    }

    internal func sendHandshake(_ handshake: PeerNetworkHandshake, completion: ((NWError?) -> Void)? = nil) {
        do {
            let payload = try handshakeEncoder(handshake)
            sendFrame(PeerNetworkFrame(kind: .handshake, payload: payload), completion: completion)
        } catch {
            NSLog("PeerConnectivity: Failed to encode Network handshake: \(error.localizedDescription)")
            completion?(.posix(.EINVAL))
        }
    }

    fileprivate func receiveNextFrame() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data = data, !data.isEmpty, !self.processReceivedData(data) {
                return
            }
            guard error == nil, !isComplete else { return }
            self.receiveNextFrame()
        }
    }

    /// Decodes received bytes and cancels the connection when the stream becomes invalid.
    @discardableResult
    internal func processReceivedData(_ data: Data) -> Bool {
        guard !isReceiveTerminal else { return false }

        do {
            try frameDecoder.append(data).forEach { frame in
                dataHandler?(frame)
            }
            return true
        } catch {
            isReceiveTerminal = true
            connection.cancel()
            invalidFrameHandler?()
            return false
        }
    }

    internal static func parameters() -> NWParameters {
        // Network transport remains internal scaffolding; before exposing it publicly,
        // provide app-configurable TLS identity or PSK verification for authenticated sessions.
        let parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = true
        return parameters
    }
}

@available(iOS 13.0, macOS 10.15, *)
internal final class NetworkPeerListener {

    internal typealias ConnectionHandler = (NetworkPeerConnection) -> Void
    internal typealias StateHandler = (NWListener.State) -> Void

    fileprivate let listener : NWListener
    fileprivate let queue : DispatchQueue
    fileprivate let connectionHandler : ConnectionHandler?
    fileprivate let stateHandler : StateHandler?

    internal init(serviceType: ServiceType,
        queue: DispatchQueue = DispatchQueue(label: "PeerConnectivity.NetworkPeerListener"),
        connectionHandler: ConnectionHandler? = nil,
        stateHandler: StateHandler? = nil) throws {
        let service = PeerNetworkBonjourService(serviceType: serviceType)
        let listener = try NWListener(using: NetworkPeerConnection.parameters())
        listener.service = NWListener.Service(name: nil, type: service.bonjourType)
        self.listener = listener
        self.queue = queue
        self.connectionHandler = connectionHandler
        self.stateHandler = stateHandler
    }

    internal func start() {
        listener.stateUpdateHandler = { [weak self] state in
            self?.stateHandler?(state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            let peerConnection = NetworkPeerConnection(connection: connection, queue: self.queue)
            self.connectionHandler?(peerConnection)
            peerConnection.start()
        }
        listener.start(queue: queue)
    }

    internal func cancel() {
        listener.cancel()
    }
}

@available(iOS 13.0, macOS 10.15, *)
internal final class NetworkPeerBrowser {

    internal typealias ResultHandler = (NWBrowser.Result.Change) -> Void
    internal typealias StateHandler = (NWBrowser.State) -> Void

    fileprivate let browser : NWBrowser
    fileprivate let queue : DispatchQueue
    fileprivate let resultHandler : ResultHandler?
    fileprivate let stateHandler : StateHandler?

    internal init(serviceType: ServiceType,
        queue: DispatchQueue = DispatchQueue(label: "PeerConnectivity.NetworkPeerBrowser"),
        resultHandler: ResultHandler? = nil,
        stateHandler: StateHandler? = nil) {
        let service = PeerNetworkBonjourService(serviceType: serviceType)
        let descriptor = NWBrowser.Descriptor.bonjour(type: service.bonjourType, domain: nil)
        browser = NWBrowser(for: descriptor, using: NetworkPeerConnection.parameters())
        self.queue = queue
        self.resultHandler = resultHandler
        self.stateHandler = stateHandler
    }

    internal func start() {
        browser.stateUpdateHandler = { [weak self] state in
            self?.stateHandler?(state)
        }
        browser.browseResultsChangedHandler = { [weak self] _, changes in
            changes.forEach { self?.resultHandler?($0) }
        }
        browser.start(queue: queue)
    }

    internal func cancel() {
        browser.cancel()
    }
}
