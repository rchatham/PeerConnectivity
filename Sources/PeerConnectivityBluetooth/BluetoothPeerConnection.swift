//
//  BluetoothPeerConnection.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import Security
import PeerConnectivity

/// A framed peer connection over an ordered stream pair, such as the streams of a `CBL2CAPChannel`.
///
/// It plays the part `NetworkPeerConnection` plays over TCP: frames go through the shared codec,
/// a `BluetoothSecureChannel` stands in for TLS, and with no TCP keepalive underneath, the stream
/// ending is the signal that the peer has gone.
@available(iOS 13.0, macOS 10.15, *)
internal final class BluetoothPeerConnection : NSObject, NetworkPeerFrameSending {

    internal typealias FrameHandler = (PeerNetworkFrame) -> Void
    internal typealias CloseHandler = () -> Void
    internal typealias ProcessedHandler = (Error?) -> Void

    fileprivate struct PendingWrite {
        let bytes : Data
        var offset : Int
        let onProcessed : ProcessedHandler?
    }

    /// Bytes requested per read; large enough to drain a burst of L2CAP packets in one pass.
    fileprivate static let readChunkLength = 65536

    fileprivate let inputStream : InputStream
    fileprivate let outputStream : OutputStream
    /// Retained for the connection's lifetime: a `CBL2CAPChannel` closes its streams when released.
    fileprivate let owner : AnyObject?
    fileprivate let queue : DispatchQueue
    fileprivate let channel : BluetoothSecureChannel
    fileprivate var frameHandler : FrameHandler?
    fileprivate var closeHandler : CloseHandler?
    fileprivate var frameDecoder = PeerNetworkFrameDecoder()
    /// Encoded frames held back until the secure channel has authenticated the peer.
    fileprivate var framesAwaitingChannel : [(bytes: Data, onProcessed: ProcessedHandler)] = []
    fileprivate var pendingWrites : [PendingWrite] = []
    fileprivate var readBuffer = [UInt8](repeating: 0, count: BluetoothPeerConnection.readChunkLength)
    fileprivate var isClosed = false
    /// Stream delegates are unretained, and Core Foundation can deliver an event already queued
    /// after the connection is released; the proxy turns such an event into a no-op.
    fileprivate let streamEvents = StreamEventProxy()
    fileprivate let peerCertificateChainLock = NSLock()
    fileprivate var storedPeerCertificateChain : [SecCertificate]?

    /// The peer's certificate, once the channel has verified it. The coordinator reads this from
    /// its own queue when the peer's identity frame arrives, which is always after verification.
    internal var peerCertificateChain : [Any]? {
        peerCertificateChainLock.lock()
        defer { peerCertificateChainLock.unlock() }
        return storedPeerCertificateChain
    }

    /// - parameter direction: `.outbound` for the side that opened the channel, which starts the handshake.
    internal convenience init(inputStream: InputStream,
        outputStream: OutputStream,
        direction: NetworkPeerConnectionDirection,
        security: PeerConnectionNetworkSecurity = .unauthenticated,
        owner: AnyObject? = nil,
        queue: DispatchQueue = DispatchQueue(label: "PeerConnectivity.BluetoothPeerConnection")) {
        self.init(inputStream: inputStream,
            outputStream: outputStream,
            channel: BluetoothSecureChannel(security: security, direction: direction),
            owner: owner,
            queue: queue)
    }

    internal init(inputStream: InputStream,
        outputStream: OutputStream,
        channel: BluetoothSecureChannel,
        owner: AnyObject? = nil,
        queue: DispatchQueue = DispatchQueue(label: "PeerConnectivity.BluetoothPeerConnection")) {
        self.inputStream = inputStream
        self.outputStream = outputStream
        self.channel = channel
        self.owner = owner
        self.queue = queue
        super.init()
        streamEvents.connection = self
    }

    deinit {
        // Released without `cancel()`: stop and unschedule the streams. Events already queued
        // reach the proxy, whose weak reference is now nil.
        if !isClosed {
            tearDownStreams()
        }
    }

    /// Opens both streams and starts the channel handshake. Handlers run on the connection's queue.
    /// `onClose` runs once, whether the remote side closed, a stream failed, the peer failed
    /// authentication, the incoming bytes were not valid frames, or `cancel()` ran.
    internal func start(onFrame: @escaping FrameHandler, onClose: @escaping CloseHandler) {
        queue.async { [self] in
            guard !isClosed else {
                onClose()
                return
            }
            frameHandler = onFrame
            closeHandler = onClose
            inputStream.delegate = streamEvents
            outputStream.delegate = streamEvents
            CFReadStreamSetDispatchQueue(inputStream, queue)
            CFWriteStreamSetDispatchQueue(outputStream, queue)
            inputStream.open()
            outputStream.open()
            do {
                enqueueWrite(try channel.start(), onProcessed: nil)
            } catch {
                close()
            }
        }
    }

    internal func cancel() {
        // Asynchronous, like `NWConnection.cancel()`: the coordinator cancels from inside its own queue.
        queue.async { [self] in close() }
    }

    internal func sendFrame(_ frame: PeerNetworkFrame, onProcessed: @escaping ProcessedHandler) {
        guard frame.payload.count <= PeerNetworkFrame.maxPayloadLength else {
            onProcessed(POSIXError(.EMSGSIZE))
            return
        }

        let bytes = frame.encoded()
        queue.async { [self] in
            guard !isClosed else {
                onProcessed(POSIXError(.ENOTCONN))
                return
            }
            guard channel.isOpen else {
                // Like data sent on an `NWConnection` before TLS completes: held, not dropped.
                framesAwaitingChannel.append((bytes, onProcessed))
                return
            }
            sendThroughChannel(bytes, onProcessed: onProcessed)
        }
    }

    fileprivate func sendThroughChannel(_ bytes: Data, onProcessed: @escaping ProcessedHandler) {
        do {
            enqueueWrite(try channel.seal(bytes), onProcessed: onProcessed)
        } catch {
            onProcessed(error)
            close()
        }
    }

    fileprivate func enqueueWrite(_ bytes: Data, onProcessed: ProcessedHandler?) {
        guard !bytes.isEmpty else { return }
        pendingWrites.append(PendingWrite(bytes: bytes, offset: 0, onProcessed: onProcessed))
        writePendingBytes()
    }

    /// Writes queued bytes until the stream is full. A frame counts as processed only once
    /// every byte is written, matching `NWConnection`'s `.contentProcessed`.
    fileprivate func writePendingBytes() {
        while !isClosed, let write = pendingWrites.first, outputStream.hasSpaceAvailable {
            let written = write.bytes.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return outputStream.write(base + write.offset, maxLength: buffer.count - write.offset)
            }
            guard written > 0 else {
                if written < 0 { close() }
                return
            }
            pendingWrites[0].offset += written
            if pendingWrites[0].offset == write.bytes.count {
                pendingWrites.removeFirst().onProcessed?(nil)
            }
        }
    }

    fileprivate func readAvailableBytes() {
        while !isClosed && inputStream.hasBytesAvailable {
            let count = inputStream.read(&readBuffer, maxLength: readBuffer.count)
            guard count > 0 else {
                if count < 0 { close() }
                return
            }
            let output : BluetoothSecureChannel.Output
            do {
                output = try channel.receive(Data(readBuffer[0..<count]))
            } catch {
                // Failed authentication or a tampered message: drop the link, as a TLS failure would.
                close()
                return
            }
            enqueueWrite(output.bytesToSend, onProcessed: nil)
            if channel.isOpen {
                releaseFramesAwaitingChannel()
            }
            deliver(output.plaintext)
        }
    }

    fileprivate func releaseFramesAwaitingChannel() {
        if let chain = channel.peerCertificateChain {
            peerCertificateChainLock.lock()
            storedPeerCertificateChain = chain
            peerCertificateChainLock.unlock()
        }
        let frames = framesAwaitingChannel
        framesAwaitingChannel.removeAll()
        frames.forEach { sendThroughChannel($0.bytes, onProcessed: $0.onProcessed) }
    }

    fileprivate func deliver(_ plaintext: Data) {
        guard !isClosed, !plaintext.isEmpty else { return }
        do {
            for frame in try frameDecoder.append(plaintext) {
                frameHandler?(frame)
            }
        } catch {
            // A framing error cannot be resynchronised, so drop the link as the Network backend does.
            close()
        }
    }

    /// Tears the link down once and fails the frames that were not fully written.
    fileprivate func close() {
        guard !isClosed else { return }
        isClosed = true
        tearDownStreams()

        let unfinished = pendingWrites.compactMap { $0.onProcessed } + framesAwaitingChannel.map { $0.onProcessed }
        let onClose = closeHandler
        pendingWrites.removeAll()
        framesAwaitingChannel.removeAll()
        frameHandler = nil
        closeHandler = nil
        unfinished.forEach { $0(POSIXError(.ENOTCONN)) }
        onClose?()
    }

    fileprivate func tearDownStreams() {
        inputStream.delegate = nil
        outputStream.delegate = nil
        CFReadStreamSetDispatchQueue(inputStream, nil)
        CFWriteStreamSetDispatchQueue(outputStream, nil)
        inputStream.close()
        outputStream.close()
        // Core Foundation may already have queued an event block for these streams, and it does
        // not retain them or their delegate. Keep the streams, the channel that owns them and the
        // delegate proxy alive until every block queued before this one has run; otherwise
        // releasing the connection right after closing it crashes inside Core Foundation.
        let retained : (InputStream, OutputStream, AnyObject?, StreamEventProxy) = (inputStream, outputStream, owner, streamEvents)
        queue.async { withExtendedLifetime(retained) {} }
    }

    fileprivate func handleStreamEvent(_ stream: Stream, _ eventCode: Stream.Event) {
        // All connection state is confined to `queue`; the streams were scheduled on it in `start`.
        dispatchPrecondition(condition: .onQueue(queue))
        switch eventCode {
        case .hasBytesAvailable:
            readAvailableBytes()
        case .hasSpaceAvailable:
            writePendingBytes()
        case .endEncountered:
            // Deliver whatever arrived before the remote side closed.
            if stream === inputStream { readAvailableBytes() }
            close()
        case .errorOccurred:
            close()
        default: break
        }
    }
}

/// Forwards stream events to a connection that may already have been released.
@available(iOS 13.0, macOS 10.15, *)
private final class StreamEventProxy : NSObject, StreamDelegate {

    /// Loading a weak reference is thread-safe and yields nil once the connection's deinit begins.
    weak var connection : BluetoothPeerConnection?

    func stream(_ stream: Stream, handle eventCode: Stream.Event) {
        connection?.handleStreamEvent(stream, eventCode)
    }
}
