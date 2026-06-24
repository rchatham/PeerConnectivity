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
internal final class NetworkPeerConnection {

    internal typealias StateHandler = (NWConnection.State) -> Void
    internal typealias DataHandler = (Data) -> Void

    fileprivate let connection : NWConnection
    fileprivate let queue : DispatchQueue
    fileprivate let stateHandler : StateHandler?
    fileprivate let dataHandler : DataHandler?

    internal init(endpoint: NWEndpoint,
        queue: DispatchQueue = DispatchQueue(label: "PeerConnectivity.NetworkPeerConnection"),
        stateHandler: StateHandler? = nil,
        dataHandler: DataHandler? = nil) {
        self.connection = NWConnection(to: endpoint, using: NetworkPeerConnection.parameters())
        self.queue = queue
        self.stateHandler = stateHandler
        self.dataHandler = dataHandler
    }

    internal init(connection: NWConnection,
        queue: DispatchQueue = DispatchQueue(label: "PeerConnectivity.NetworkPeerConnection"),
        stateHandler: StateHandler? = nil,
        dataHandler: DataHandler? = nil) {
        self.connection = connection
        self.queue = queue
        self.stateHandler = stateHandler
        self.dataHandler = dataHandler
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
        connection.send(content: frame.encoded(), completion: .contentProcessed { error in
            completion?(error)
        })
    }

    internal func sendHandshake(_ handshake: PeerNetworkHandshake, completion: ((NWError?) -> Void)? = nil) {
        do {
            let payload = try JSONEncoder().encode(handshake)
            sendFrame(PeerNetworkFrame(kind: .handshake, payload: payload), completion: completion)
        } catch {
            NSLog("PeerConnectivity: Failed to encode Network handshake: \(error.localizedDescription)")
            completion?(nil)
        }
    }

    fileprivate func receiveNextFrame() {
        connection.receive(minimumIncompleteLength: 5, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, let frame = PeerNetworkFrame.decode(data) {
                self?.dataHandler?(frame.payload)
            }
            guard error == nil, !isComplete else { return }
            self?.receiveNextFrame()
        }
    }

    internal static func parameters() -> NWParameters {
        let parameters = NWParameters.tcp
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
