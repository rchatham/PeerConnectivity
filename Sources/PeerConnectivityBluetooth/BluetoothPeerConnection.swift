//
//  BluetoothPeerConnection.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import PeerConnectivity

/// A framed peer connection over an ordered stream pair, such as the streams of a `CBL2CAPChannel`.
///
/// It plays the part `NetworkPeerConnection` plays over TCP: bytes go through the shared frame codec,
/// and with no TCP keepalive underneath, the stream ending is the signal that the peer has gone.
@available(iOS 13.0, macOS 10.15, *)
internal final class BluetoothPeerConnection : NSObject, NetworkPeerFrameSending {

    internal typealias FrameHandler = (PeerNetworkFrame) -> Void
    internal typealias CloseHandler = () -> Void

    fileprivate struct PendingWrite {
        let bytes : Data
        var offset : Int
        let onProcessed : (Error?) -> Void
    }

    /// Bytes requested per read; large enough to drain a burst of L2CAP packets in one pass.
    fileprivate static let readChunkLength = 65536

    fileprivate let inputStream : InputStream
    fileprivate let outputStream : OutputStream
    /// Retained for the connection's lifetime: a `CBL2CAPChannel` closes its streams when released.
    fileprivate let owner : AnyObject?
    fileprivate let queue : DispatchQueue
    fileprivate var frameHandler : FrameHandler?
    fileprivate var closeHandler : CloseHandler?
    fileprivate var frameDecoder = PeerNetworkFrameDecoder()
    fileprivate var pendingWrites : [PendingWrite] = []
    fileprivate var isClosed = false

    internal init(inputStream: InputStream,
        outputStream: OutputStream,
        owner: AnyObject? = nil,
        queue: DispatchQueue = DispatchQueue(label: "PeerConnectivity.BluetoothPeerConnection")) {
        self.inputStream = inputStream
        self.outputStream = outputStream
        self.owner = owner
        self.queue = queue
        super.init()
    }

    deinit {
        // Stream delegates are not retained; never leave a stream pointing at a freed connection.
        inputStream.delegate = nil
        outputStream.delegate = nil
    }

    /// Opens both streams. Handlers run on the connection's queue. `onClose` runs once, whether the
    /// remote side closed, a stream failed, the incoming bytes were not valid frames, or `cancel()` ran.
    internal func start(onFrame: @escaping FrameHandler, onClose: @escaping CloseHandler) {
        queue.async { [self] in
            guard !isClosed else {
                onClose()
                return
            }
            frameHandler = onFrame
            closeHandler = onClose
            inputStream.delegate = self
            outputStream.delegate = self
            CFReadStreamSetDispatchQueue(inputStream, queue)
            CFWriteStreamSetDispatchQueue(outputStream, queue)
            inputStream.open()
            outputStream.open()
        }
    }

    internal func cancel() {
        // Asynchronous, like `NWConnection.cancel()`: the coordinator cancels from inside its own queue.
        queue.async { [self] in close() }
    }

    internal func sendFrame(_ frame: PeerNetworkFrame, onProcessed: @escaping (Error?) -> Void) {
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
            pendingWrites.append(PendingWrite(bytes: bytes, offset: 0, onProcessed: onProcessed))
            writePendingBytes()
        }
    }

    /// Writes queued frames until the stream is full. A frame counts as processed only once
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
                pendingWrites.removeFirst().onProcessed(nil)
            }
        }
    }

    fileprivate func readAvailableBytes() {
        var buffer = [UInt8](repeating: 0, count: BluetoothPeerConnection.readChunkLength)
        while !isClosed && inputStream.hasBytesAvailable {
            let count = inputStream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else {
                if count < 0 { close() }
                return
            }
            do {
                for frame in try frameDecoder.append(Data(buffer[0..<count])) {
                    frameHandler?(frame)
                }
            } catch {
                // A framing error cannot be resynchronised, so drop the link as the Network backend does.
                close()
                return
            }
        }
    }

    /// Tears the link down once and fails the frames that were not fully written.
    fileprivate func close() {
        guard !isClosed else { return }
        isClosed = true

        inputStream.delegate = nil
        outputStream.delegate = nil
        CFReadStreamSetDispatchQueue(inputStream, nil)
        CFWriteStreamSetDispatchQueue(outputStream, nil)
        inputStream.close()
        outputStream.close()

        let unfinishedWrites = pendingWrites
        let onClose = closeHandler
        pendingWrites.removeAll()
        frameHandler = nil
        closeHandler = nil
        unfinishedWrites.forEach { $0.onProcessed(POSIXError(.ENOTCONN)) }
        onClose?()
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension BluetoothPeerConnection : StreamDelegate {

    internal func stream(_ stream: Stream, handle eventCode: Stream.Event) {
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
