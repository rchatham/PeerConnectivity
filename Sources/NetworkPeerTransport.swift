//
//  NetworkPeerTransport.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import Network
import Security

@available(iOS 13.0, macOS 10.15, *)
internal protocol NetworkPeerListening {
    func start()
    func cancel()
}

@available(iOS 13.0, macOS 10.15, *)
internal protocol NetworkPeerBrowsing {
    func start()
    func cancel()
}

@available(iOS 13.0, macOS 10.15, *)
internal final class NetworkPeerConnection : NetworkPeerConnectionCancellable {

    internal typealias StateHandler = (NWConnection.State) -> Void
    internal typealias DataHandler = (PeerNetworkFrame) -> Void

    fileprivate let connection : NWConnection
    fileprivate let queue : DispatchQueue
    fileprivate var stateHandler : StateHandler?
    fileprivate var dataHandler : DataHandler?
    fileprivate var frameDecoder = PeerNetworkFrameDecoder()

    internal init(endpoint: NWEndpoint,
        queue: DispatchQueue = DispatchQueue(label: "PeerConnectivity.NetworkPeerConnection"),
        security: PeerConnectionNetworkSecurity = .unauthenticated,
        stateHandler: StateHandler? = nil,
        dataHandler: DataHandler? = nil) {
        self.connection = NWConnection(to: endpoint, using: NetworkPeerConnection.parameters(security: security))
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

    internal func setDataHandler(_ dataHandler: DataHandler?) {
        self.dataHandler = dataHandler
    }

    internal func setStateHandler(_ stateHandler: StateHandler?) {
        self.stateHandler = stateHandler
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.frameDecoder.append(data).forEach { frame in
                    self?.dataHandler?(frame)
                }
            }
            guard error == nil, !isComplete else {
                self?.cancel()
                self?.stateHandler?(.cancelled)
                return
            }
            self?.receiveNextFrame()
        }
    }

    internal static func parameters(security: PeerConnectionNetworkSecurity = .unauthenticated) -> NWParameters {
        let parameters : NWParameters
        switch security {
        case .unauthenticated:
            parameters = NWParameters.tcp
        case .preSharedKey(let key):
            precondition(!key.isEmpty, "PeerConnectivity: Network pre-shared key must not be empty")
            let options = NWProtocolTLS.Options()
            sec_protocol_options_add_pre_shared_key(options.securityProtocolOptions,
                dispatchData(from: key),
                dispatchData(from: Data("PeerConnectivity.NetworkFramework.PSK.v1".utf8)))
            parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        }
        parameters.includePeerToPeer = true
        return parameters
    }

    fileprivate static func dispatchData(from data: Data) -> dispatch_data_t {
        return data.withUnsafeBytes { buffer in
            return DispatchData(bytes: buffer) as dispatch_data_t
        }
    }
}

@available(iOS 13.0, macOS 10.15, *)
internal final class NetworkPeerListener : NetworkPeerListening {

    internal typealias ConnectionHandler = (NetworkPeerConnection) -> Void
    internal typealias StateHandler = (NWListener.State) -> Void

    fileprivate let listener : NWListener
    fileprivate let queue : DispatchQueue
    fileprivate let connectionHandler : ConnectionHandler?
    fileprivate let stateHandler : StateHandler?
    fileprivate let connectionFactory : (NWConnection, DispatchQueue) -> NetworkPeerConnection

    internal init(serviceType: ServiceType,
        identity: PeerIdentity? = nil,
        queue: DispatchQueue = DispatchQueue(label: "PeerConnectivity.NetworkPeerListener"),
        security: PeerConnectionNetworkSecurity = .unauthenticated,
        connectionHandler: ConnectionHandler? = nil,
        stateHandler: StateHandler? = nil,
        connectionFactory: @escaping (NWConnection, DispatchQueue) -> NetworkPeerConnection = { connection, queue in
            return NetworkPeerConnection(connection: connection, queue: queue)
        }) throws {
        let service = PeerNetworkBonjourService(serviceType: serviceType)
        let listener = try NWListener(using: NetworkPeerConnection.parameters(security: security))
        if let identity = identity {
            let txtRecord = NWTXTRecord(PeerNetworkDiscoveryInfo(identity: identity).txtRecordDictionary)
            listener.service = NWListener.Service(name: nil, type: service.bonjourType, domain: nil, txtRecord: txtRecord)
        } else {
            listener.service = NWListener.Service(name: nil, type: service.bonjourType)
        }
        self.listener = listener
        self.queue = queue
        self.connectionHandler = connectionHandler
        self.stateHandler = stateHandler
        self.connectionFactory = connectionFactory
    }

    internal func start() {
        listener.stateUpdateHandler = { [weak self] state in
            self?.stateHandler?(state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            let peerConnection = self.connectionFactory(connection, self.queue)
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
internal final class NetworkPeerBrowser : NetworkPeerBrowsing {

    internal typealias ResultHandler = (NWBrowser.Result.Change) -> Void
    internal typealias StateHandler = (NWBrowser.State) -> Void

    fileprivate let browser : NWBrowser
    fileprivate let queue : DispatchQueue
    fileprivate var resultHandler : ResultHandler?
    fileprivate let stateHandler : StateHandler?

    internal init(serviceType: ServiceType,
        queue: DispatchQueue = DispatchQueue(label: "PeerConnectivity.NetworkPeerBrowser"),
        security: PeerConnectionNetworkSecurity = .unauthenticated,
        resultHandler: ResultHandler? = nil,
        stateHandler: StateHandler? = nil) {
        let service = PeerNetworkBonjourService(serviceType: serviceType)
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: service.bonjourType, domain: nil)
        browser = NWBrowser(for: descriptor, using: NetworkPeerConnection.parameters(security: security))
        self.queue = queue
        self.resultHandler = resultHandler
        self.stateHandler = stateHandler
    }

    internal func setResultHandler(_ resultHandler: ResultHandler?) {
        self.resultHandler = resultHandler
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
