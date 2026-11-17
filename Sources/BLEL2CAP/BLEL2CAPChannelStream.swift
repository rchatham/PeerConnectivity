//
//  BLEL2CAPChannelStream.swift
//  PeerConnectivity
//
//  SPIKE: feasibility prototype for a Bluetooth LE L2CAP transport. Internal only;
//  not wired into PeerConnectionManager. See Spikes/BLEL2CAPSpike/README.md.
//

#if canImport(CoreBluetooth)
import CoreBluetooth
import Foundation

/// Carries `PeerNetworkFrame`s (the same 1-byte kind + 4-byte big-endian length framing the
/// Network backend uses) over the byte streams of an open `CBL2CAPChannel`.
///
/// L2CAP connection-oriented channels give an ordered, reliable byte stream with credit-based
/// flow control, so the framing only has to delimit messages. Both streams are scheduled on a
/// private thread's run loop: CoreBluetooth hands out ordinary `InputStream`/`OutputStream`
/// objects that need a run loop to deliver events.
internal final class BLEL2CAPChannelStream : NSObject, StreamDelegate {

    internal enum CloseReason : Equatable {
        case localCancel
        case endOfStream
        case streamError(String)
        case invalidFrame
    }

    internal let channel : CBL2CAPChannel
    internal var onFrame : ((PeerNetworkFrame) -> Void)?
    internal var onClose : ((CloseReason) -> Void)?

    fileprivate let callbackQueue : DispatchQueue
    fileprivate var decoder = PeerNetworkFrameDecoder()
    fileprivate var pendingWrite = Data()
    fileprivate var writeOffset = 0
    fileprivate var isClosed = false
    fileprivate var thread : Thread?
    fileprivate var runLoop : CFRunLoop?
    fileprivate let runLoopReady = DispatchSemaphore(value: 0)
    fileprivate var readBuffer = [UInt8](repeating: 0, count: 16 * 1024)

    /// Total bytes the output stream accepted. The spike reads this to measure throughput.
    internal private(set) var bytesWritten : Int = 0

    internal init(channel: CBL2CAPChannel, callbackQueue: DispatchQueue) {
        self.channel = channel
        self.callbackQueue = callbackQueue
        super.init()
    }

    internal func open() {
        let thread = Thread { [weak self] in
            guard let self = self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            let runLoop = RunLoop.current
            self.channel.inputStream.delegate = self
            self.channel.outputStream.delegate = self
            self.channel.inputStream.schedule(in: runLoop, forMode: .default)
            self.channel.outputStream.schedule(in: runLoop, forMode: .default)
            self.channel.inputStream.open()
            self.channel.outputStream.open()
            self.runLoopReady.signal()
            while !self.isClosed {
                _ = runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 1))
            }
        }
        thread.name = "PeerConnectivity.BLEL2CAP"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
        runLoopReady.wait()
    }

    /// Queues one frame. Safe to call from any thread; writes happen on the stream thread.
    internal func send(_ frame: PeerNetworkFrame) {
        let encoded = frame.encoded()
        perform { [weak self] in
            guard let self = self, !self.isClosed else { return }
            self.pendingWrite.append(encoded)
            self.drainWrites()
        }
    }

    internal func close() {
        perform { [weak self] in
            self?.finish(.localCancel)
        }
    }

    // MARK: StreamDelegate (stream thread)

    internal func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            readAvailable()
        case .hasSpaceAvailable:
            drainWrites()
        case .endEncountered:
            finish(.endOfStream)
        case .errorOccurred:
            finish(.streamError(aStream.streamError.map { String(describing: $0) } ?? "unknown"))
        default:
            break
        }
    }

    // MARK: Private (stream thread)

    fileprivate func readAvailable() {
        guard let input = channel.inputStream else { return }
        var received = Data()
        while input.hasBytesAvailable {
            let count = input.read(&readBuffer, maxLength: readBuffer.count)
            if count <= 0 { break }
            received.append(readBuffer, count: count)
        }
        guard !received.isEmpty else { return }
        do {
            let frames = try decoder.append(received)
            guard !frames.isEmpty else { return }
            callbackQueue.async { [weak self] in
                frames.forEach { self?.onFrame?($0) }
            }
        } catch {
            finish(.invalidFrame)
        }
    }

    fileprivate func drainWrites() {
        guard let output = channel.outputStream else { return }
        while writeOffset < pendingWrite.count && output.hasSpaceAvailable {
            let written = pendingWrite.withUnsafeBytes { bytes -> Int in
                guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return output.write(base + writeOffset, maxLength: pendingWrite.count - writeOffset)
            }
            if written <= 0 { break }
            bytesWritten += written
            writeOffset += written
        }
        // Compact lazily so a large queued burst is not copied once per write.
        if writeOffset == pendingWrite.count {
            pendingWrite.removeAll(keepingCapacity: true)
            writeOffset = 0
        } else if writeOffset > 256 * 1024 {
            pendingWrite.removeFirst(writeOffset)
            writeOffset = 0
        }
    }

    fileprivate func finish(_ reason: CloseReason) {
        guard !isClosed else { return }
        isClosed = true
        channel.inputStream.close()
        channel.outputStream.close()
        channel.inputStream.remove(from: .current, forMode: .default)
        channel.outputStream.remove(from: .current, forMode: .default)
        callbackQueue.async { [weak self] in
            self?.onClose?(reason)
        }
    }

    fileprivate func perform(_ block: @escaping () -> Void) {
        guard let runLoop = runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }
}
#endif
