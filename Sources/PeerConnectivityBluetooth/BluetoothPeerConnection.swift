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
    /// Every stream event and all connection state live on this thread's run loop.
    fileprivate let streams = BluetoothStreamThread.shared
    fileprivate let channel : BluetoothSecureChannel
    fileprivate var frameHandler : FrameHandler?
    fileprivate var closeHandler : CloseHandler?
    fileprivate var frameDecoder = PeerNetworkFrameDecoder()
    /// Encoded frames held back until the secure channel has authenticated the peer.
    fileprivate var framesAwaitingChannel : [(bytes: Data, onProcessed: ProcessedHandler)] = []
    fileprivate var pendingWrites : [PendingWrite] = []
    fileprivate var readBuffer = [UInt8](repeating: 0, count: BluetoothPeerConnection.readChunkLength)
    fileprivate var isClosed = false
    /// Stream delegates are unretained; between the connection's release and its streams being
    /// unscheduled, the proxy turns any event into a no-op.
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
        owner: AnyObject? = nil) {
        self.init(inputStream: inputStream,
            outputStream: outputStream,
            channel: BluetoothSecureChannel(security: security, direction: direction),
            owner: owner)
    }

    internal init(inputStream: InputStream,
        outputStream: OutputStream,
        channel: BluetoothSecureChannel,
        owner: AnyObject? = nil) {
        self.inputStream = inputStream
        self.outputStream = outputStream
        self.channel = channel
        self.owner = owner
        super.init()
        streamEvents.connection = self
    }

    deinit {
        // Released without `cancel()`: unschedule and close the streams on their thread. Until
        // then, events reach the proxy, whose weak reference is now nil.
        if !isClosed {
            tearDownStreams()
        }
    }

    /// Opens both streams and starts the channel handshake. Handlers run on the Bluetooth stream
    /// thread. `onClose` runs once, whether the remote side closed, a stream failed, the peer failed
    /// authentication, the incoming bytes were not valid frames, or `cancel()` ran.
    internal func start(onFrame: @escaping FrameHandler, onClose: @escaping CloseHandler) {
        streams.perform { [self] in
            guard !isClosed else {
                onClose()
                return
            }
            frameHandler = onFrame
            closeHandler = onClose
            inputStream.delegate = streamEvents
            outputStream.delegate = streamEvents
            inputStream.schedule(in: streams.runLoop, forMode: .default)
            outputStream.schedule(in: streams.runLoop, forMode: .default)
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
        streams.perform { [self] in close() }
    }

    internal func sendFrame(_ frame: PeerNetworkFrame, onProcessed: @escaping ProcessedHandler) {
        guard frame.payload.count <= PeerNetworkFrame.maxPayloadLength else {
            onProcessed(POSIXError(.EMSGSIZE))
            return
        }

        let bytes = frame.encoded()
        streams.perform { [self] in
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

    /// Unschedules and closes the streams on the stream thread, where their events are delivered,
    /// so no event can arrive afterwards. Streams were scheduled on a run loop rather than with
    /// `CFReadStreamSetDispatchQueue`: Core Foundation's dispatch-queue delivery could still run an
    /// event for a stream after it was unscheduled and released, crashing inside Core Foundation.
    fileprivate func tearDownStreams() {
        // From deinit the connection is going away, so capture the streams, not `self`.
        let input = inputStream
        let output = outputStream
        let retained : (AnyObject?, StreamEventProxy) = (owner, streamEvents)
        let runLoop : RunLoop = streams.runLoop
        let tearDown = {
            withExtendedLifetime(retained) {
                for stream in [input, output] as [Stream] {
                    stream.remove(from: runLoop, forMode: .default)
                    stream.delegate = nil
                    stream.close()
                }
            }
        }
        if streams.isCurrent {
            tearDown()
        } else {
            streams.perform(tearDown)
        }
    }

    fileprivate func handleStreamEvent(_ stream: Stream, _ eventCode: Stream.Event) {
        // All connection state is confined to the stream thread, where the streams are scheduled.
        assert(streams.isCurrent, "Bluetooth stream event off the stream thread")
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

/// One thread with a run loop for every Bluetooth stream. Bluetooth throughput is low, so one
/// thread is enough, and work is queued with `perform` in the order it is submitted.
@available(iOS 13.0, macOS 10.15, *)
internal final class BluetoothStreamThread : Thread {

    internal static let shared : BluetoothStreamThread = {
        let thread = BluetoothStreamThread()
        thread.name = "PeerConnectivity.BluetoothStreams"
        thread.qualityOfService = .userInitiated
        thread.start()
        thread.started.wait()
        return thread
    }()

    fileprivate let started = DispatchSemaphore(value: 0)
    fileprivate var cfRunLoop : CFRunLoop!
    internal fileprivate(set) var runLoop : RunLoop!

    internal var isCurrent : Bool {
        return Thread.current === self
    }

    internal override func main() {
        runLoop = RunLoop.current
        cfRunLoop = CFRunLoopGetCurrent()
        // A port keeps the run loop running when no stream is scheduled.
        runLoop.add(NSMachPort(), forMode: .default)
        started.signal()
        while true {
            autoreleasepool {
                _ = runLoop.run(mode: .default, before: .distantFuture)
            }
        }
    }

    /// Runs `block` on this thread, after any work submitted before it.
    internal func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(cfRunLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(cfRunLoop)
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
