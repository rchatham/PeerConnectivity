//
//  BluetoothPeerConnectionTests.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import XCTest
import PeerConnectivity
@testable import PeerConnectivityBluetooth

@available(iOS 13.0, macOS 10.15, *)
final class BluetoothPeerConnectionTests : XCTestCase {

    // MARK: - Connection pairs

    func testFramesCrossSmallBuffersInBothDirectionsInOrder() {
        // A 7-byte buffer forces every frame to be written in pieces and read in pieces.
        let (first, second) = makeConnectionPair(bufferSize: 7)
        let large = PeerNetworkFrame(kind: .data, payload: Data((0..<4096).map { UInt8($0 % 251) }))
        let outbound = [
            PeerNetworkFrame(kind: .handshake, payload: Data("hello".utf8)),
            large,
            PeerNetworkFrame(kind: .admitted, payload: Data()),
        ]
        let inbound = [PeerNetworkFrame(kind: .data, payload: Data("reply".utf8))]

        let secondReceived = FrameRecorder(expecting: outbound.count, description: "second receives")
        let firstReceived = FrameRecorder(expecting: inbound.count, description: "first receives")
        first.start(onFrame: firstReceived.record, onClose: {})
        second.start(onFrame: secondReceived.record, onClose: {})

        let processed = expectation(description: "every frame fully written")
        processed.expectedFulfillmentCount = outbound.count + inbound.count
        outbound.forEach { frame in
            first.sendFrame(frame) { error in
                XCTAssertNil(error)
                processed.fulfill()
            }
        }
        inbound.forEach { frame in
            second.sendFrame(frame) { error in
                XCTAssertNil(error)
                processed.fulfill()
            }
        }

        wait(for: [processed, secondReceived.expectation, firstReceived.expectation], timeout: 5)
        XCTAssertEqual(secondReceived.frames, outbound)
        XCTAssertEqual(firstReceived.frames, inbound)
    }

    func testCancelClosesBothSidesOnceAndFailsUnfinishedWrites() {
        // Nobody reads the second connection's input, so the large frame cannot finish writing.
        let (first, second) = makeConnectionPair(bufferSize: 16)
        let firstClosed = expectation(description: "first reports close")
        let secondClosed = expectation(description: "second sees the remote close")
        first.start(onFrame: { _ in }, onClose: { firstClosed.fulfill() })

        let failedWrite = expectation(description: "unfinished write fails")
        first.sendFrame(PeerNetworkFrame(kind: .data, payload: Data(count: 1024))) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .ENOTCONN)
            failedWrite.fulfill()
        }
        first.cancel()
        first.cancel()
        wait(for: [failedWrite, firstClosed], timeout: 5)

        second.start(onFrame: { _ in }, onClose: { secondClosed.fulfill() })
        wait(for: [secondClosed], timeout: 5)

        let sendAfterClose = expectation(description: "send after close fails")
        first.sendFrame(PeerNetworkFrame(kind: .data, payload: Data())) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .ENOTCONN)
            sendAfterClose.fulfill()
        }
        wait(for: [sendAfterClose], timeout: 5)
    }

    func testCancelBeforeStartStillReportsClose() {
        let (first, _) = makeConnectionPair(bufferSize: 16)
        let closed = expectation(description: "close reported at start")
        first.cancel()
        first.start(onFrame: { _ in XCTFail("no frames after cancel") }, onClose: { closed.fulfill() })
        wait(for: [closed], timeout: 5)
    }

    func testOversizedFrameFailsWithoutWriting() {
        let (first, _) = makeConnectionPair(bufferSize: 16)
        let oversized = PeerNetworkFrame(kind: .data, payload: Data(count: PeerNetworkFrame.maxPayloadLength + 1))
        var reportedError : Error?
        first.sendFrame(oversized) { reportedError = $0 }
        XCTAssertEqual((reportedError as? POSIXError)?.code, .EMSGSIZE)
    }

    // MARK: - Raw bytes from the remote side

    func testDecodesFramesCoalescedIntoOneWriteAndSplitAcrossWrites() {
        let remote = RawRemote()
        let frames = [
            PeerNetworkFrame(kind: .handshake, payload: Data("one".utf8)),
            PeerNetworkFrame(kind: .data, payload: Data("two".utf8)),
            PeerNetworkFrame(kind: .data, payload: Data("three".utf8)),
        ]
        let received = FrameRecorder(expecting: frames.count, description: "all frames decoded")
        remote.connection.start(onFrame: received.record, onClose: {})

        // Two whole frames in one write, then the third split mid-header and mid-payload.
        let third = frames[2].encoded()
        remote.write(frames[0].encoded() + frames[1].encoded() + third.prefix(3))
        remote.write(third.dropFirst(3).prefix(4))
        remote.write(third.dropFirst(7))

        wait(for: [received.expectation], timeout: 5)
        XCTAssertEqual(received.frames, frames)
    }

    func testInvalidFrameClosesConnection() {
        let remote = RawRemote()
        let closed = expectation(description: "invalid stream closes the connection")
        remote.connection.start(onFrame: { _ in XCTFail("no frame from an invalid stream") },
            onClose: { closed.fulfill() })

        remote.write(Data([0xFF, 0, 0, 0, 1, 0]))
        wait(for: [closed], timeout: 5)
    }

    func testRemoteCloseDeliversBufferedFramesThenReportsClose() {
        let remote = RawRemote()
        let frame = PeerNetworkFrame(kind: .data, payload: Data("last words".utf8))
        let received = FrameRecorder(expecting: 1, description: "frame sent before close arrives")
        let closed = expectation(description: "remote close reported")
        remote.connection.start(onFrame: received.record, onClose: { closed.fulfill() })

        remote.write(frame.encoded())
        remote.close()
        wait(for: [received.expectation, closed], timeout: 5, enforceOrder: true)
        XCTAssertEqual(received.frames, [frame])
    }

    // MARK: - Helpers

    /// Two connections whose streams are joined by bound pairs of the given buffer size.
    private func makeConnectionPair(bufferSize: Int) -> (BluetoothPeerConnection, BluetoothPeerConnection) {
        let (firstIn, secondOut) = makeBoundStreams(bufferSize: bufferSize)
        let (secondIn, firstOut) = makeBoundStreams(bufferSize: bufferSize)
        return (BluetoothPeerConnection(inputStream: firstIn, outputStream: firstOut),
                BluetoothPeerConnection(inputStream: secondIn, outputStream: secondOut))
    }
}

/// A connection whose remote side is driven byte by byte from the test.
@available(iOS 13.0, macOS 10.15, *)
private final class RawRemote {
    let connection : BluetoothPeerConnection
    private let remoteOutput : OutputStream

    init() {
        let (connectionIn, remoteOut) = makeBoundStreams(bufferSize: 4096)
        let (_, connectionOut) = makeBoundStreams(bufferSize: 4096)
        connection = BluetoothPeerConnection(inputStream: connectionIn, outputStream: connectionOut)
        remoteOutput = remoteOut
        remoteOutput.open()
    }

    /// Writes synchronously; the bound buffer is large enough that every test write fits.
    func write<Bytes: DataProtocol>(_ bytes: Bytes) {
        let data = Data(bytes)
        let written = data.withUnsafeBytes {
            remoteOutput.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count)
        }
        XCTAssertEqual(written, data.count)
    }

    func close() {
        remoteOutput.close()
    }
}

/// Collects frames on the connection's queue and fulfils once the expected number arrived.
private final class FrameRecorder {
    let expectation : XCTestExpectation
    private let lock = NSLock()
    private var storedFrames : [PeerNetworkFrame] = []

    var frames : [PeerNetworkFrame] {
        lock.lock(); defer { lock.unlock() }
        return storedFrames
    }

    init(expecting count: Int, description: String) {
        expectation = XCTestExpectation(description: description)
        expectation.expectedFulfillmentCount = count
        expectation.assertForOverFulfill = true
    }

    func record(_ frame: PeerNetworkFrame) {
        lock.lock()
        storedFrames.append(frame)
        lock.unlock()
        expectation.fulfill()
    }
}

private func makeBoundStreams(bufferSize: Int) -> (InputStream, OutputStream) {
    var input : InputStream?
    var output : OutputStream?
    Stream.getBoundStreams(withBufferSize: bufferSize, inputStream: &input, outputStream: &output)
    return (input!, output!)
}
