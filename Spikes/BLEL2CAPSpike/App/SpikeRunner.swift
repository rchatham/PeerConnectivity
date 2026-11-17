//
//  SpikeRunner.swift
//  BLEL2CAPSpike
//

import CoreBluetooth
import Foundation
import QuartzCore
import UIKit
@testable import PeerConnectivity

/// Spike wire ops carried inside `PeerNetworkFrame(kind: .data)` payloads:
///   [op u8][seq u32][body]
enum SpikeOp: UInt8 {
    case ping = 1, pong = 2, bulk = 3, bulkEnd = 4, bulkAck = 5
}

// State is confined to `queue`; @unchecked silences the spike's closure-capture warnings.
final class SpikeRunner: ObservableObject, @unchecked Sendable {

    @Published var logText = ""
    @Published var role: String?

    private let queue = DispatchQueue(label: "spike.ble", qos: .userInitiated)
    private let launchTime = CACurrentMediaTime()

    // All state below is touched on `queue` only.
    private var lines: [String] = []
    private var events: [[String: Any]] = []
    private var summary: [String: Any] = [:]
    private var advertiser: BLEL2CAPAdvertiser?
    private var browser: BLEL2CAPBrowser?
    private var stream: BLEL2CAPChannelStream?
    private var appState = "active"
    private var scanStart: CFTimeInterval = 0
    private var connectStepStart: CFTimeInterval = 0
    private var disconnectedAt: CFTimeInterval?
    private var pending: [UInt32: (CFTimeInterval, Data) -> Void] = [:]
    private var bulkAck: ((UInt32, UInt64, CFTimeInterval) -> Void)?
    private var channelWaiter: (() -> Void)?
    private var nextSeq: UInt32 = 1
    private var bulkFrames: UInt32 = 0
    private var bulkBytes: UInt64 = 0
    private var bulkFirstAt: CFTimeInterval = 0
    private var started = false

    init() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.appState = "background"; self?.log("app entered background") }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.appState = "active"; self?.log("app entering foreground") }
        }
    }

    func startFromLaunchArguments() {
        if let role = UserDefaults.standard.string(forKey: "role") {
            start(role: role)
        }
    }

    func start(role: String) {
        guard !started else { return }
        started = true
        self.role = role
        UIApplication.shared.isIdleTimerDisabled = true
        let soak = UserDefaults.standard.object(forKey: "soak") as? Int
            ?? Int(UserDefaults.standard.string(forKey: "soak") ?? "") ?? 120
        queue.async {
            self.summary["role"] = role
            self.summary["device"] = Self.modelIdentifier()
            self.summary["deviceName"] = UIDevice.current.name
            self.summary["systemVersion"] = UIDevice.current.systemVersion
            self.summary["bundleId"] = Bundle.main.bundleIdentifier ?? "?"
            self.summary["backgroundModes"] = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") ?? []
            self.log("start role=\(role) device=\(Self.modelIdentifier()) iOS \(UIDevice.current.systemVersion)")
            if role == "central" {
                self.startBrowser()
                Task { await self.runCentral(soakSeconds: soak) }
            } else {
                self.startAdvertiser()
            }
        }
    }

    // MARK: Peripheral (echo)

    private func startAdvertiser() {
        let advertiser = BLEL2CAPAdvertiser(localName: "HermesSpike", queue: queue)
        advertiser.onEvent = { [weak self] event in
            guard let self = self else { return }
            switch event {
            case .stateChanged(let state):
                self.log("peripheral state=\(state.rawValue)")
            case .published(let psm):
                self.log("published PSM=\(psm)")
            case .advertisingStarted(let error):
                self.log("advertising started error=\(String(describing: error))")
            case .channelOpened(let channel):
                self.log("peripheral channel opened PSM=\(channel.psm)", key: "peripheralChannelOpen")
                self.attach(channel)
            case .channelFailed(let error):
                self.log("peripheral channel failed \(error)")
            }
        }
        self.advertiser = advertiser
    }

    private func handlePeripheralFrame(op: SpikeOp, seq: UInt32, body: Data) {
        switch op {
        case .ping:
            var reply = Self.header(.pong, seq)
            reply.append(appState == "active" ? 1 : 0)
            reply.append(body)
            stream?.send(PeerNetworkFrame(kind: .data, payload: reply))
        case .bulk:
            if bulkFrames == 0 { bulkFirstAt = CACurrentMediaTime() }
            bulkFrames += 1
            bulkBytes += UInt64(body.count)
        case .bulkEnd:
            let elapsed = CACurrentMediaTime() - bulkFirstAt
            log("bulk received frames=\(bulkFrames) bytes=\(bulkBytes) firstToEnd=\(Self.ms(elapsed))ms")
            var reply = Self.header(.bulkAck, seq)
            reply.append(contentsOf: Self.bytes(bulkFrames))
            reply.append(contentsOf: Self.bytes(bulkBytes))
            stream?.send(PeerNetworkFrame(kind: .data, payload: reply))
            bulkFrames = 0
            bulkBytes = 0
        default:
            break
        }
    }

    // MARK: Central (measure)

    private func startBrowser() {
        let browser = BLEL2CAPBrowser(queue: queue)
        browser.onEvent = { [weak self] event in
            guard let self = self else { return }
            let now = CACurrentMediaTime()
            switch event {
            case .stateChanged(let state):
                self.log("central state=\(state.rawValue)")
            case .scanStarted:
                self.scanStart = now
                self.log("scan started")
            case .discovered(let name, let rssi):
                self.connectStepStart = now
                self.log("discovered name=\(name ?? "-") rssi=\(rssi) after \(Self.ms(now - self.scanStart))ms",
                    key: self.disconnectedAt == nil ? "discoverMs" : nil, value: Self.ms(now - self.scanStart))
            case .connected:
                self.log("LE connected +\(Self.ms(now - self.connectStepStart))ms",
                    key: self.disconnectedAt == nil ? "leConnectMs" : nil, value: Self.ms(now - self.connectStepStart))
            case .servicesDiscovered:
                self.log("services discovered +\(Self.ms(now - self.connectStepStart))ms")
            case .psmRead(let psm):
                self.log("PSM \(psm) read +\(Self.ms(now - self.connectStepStart))ms")
            case .channelOpened(let channel):
                let connectMs = Self.ms(now - self.connectStepStart)
                let totalMs = Self.ms(now - self.scanStart)
                if let disconnectedAt = self.disconnectedAt {
                    self.log("RECONNECTED channel open \(Self.ms(now - disconnectedAt))ms after drop (scan->open \(totalMs)ms)",
                        key: "reconnectMs", value: Self.ms(now - disconnectedAt))
                    self.disconnectedAt = nil
                } else {
                    self.summary["l2capConnectMs"] = connectMs
                    self.summary["scanToChannelMs"] = totalMs
                    self.log("L2CAP channel open: discover->open \(connectMs)ms, scan->open \(totalMs)ms")
                }
                self.attach(channel)
                self.channelWaiter?()
                self.channelWaiter = nil
            case .failed(let reason):
                self.log("central failure: \(reason)")
            case .disconnected(let error):
                self.log("LE disconnected error=\(String(describing: error))")
                self.handleCentralDrop()
            }
        }
        self.browser = browser
    }

    private func handleCentralDrop() {
        guard disconnectedAt == nil else { return }
        disconnectedAt = CACurrentMediaTime()
        stream?.close()
        stream = nil
        browser?.stop()
        browser = nil
        log("restarting scan to reconnect")
        startBrowser()
    }

    private func runCentral(soakSeconds: Int) async {
        await waitForChannel(timeout: 120)
        guard await isConnected() else {
            log("no channel within 120s, giving up")
            return
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let message = Self.samplePeerMessageJSON(targetBytes: 1024)
        await measureRTT(label: "rtt1KB", payload: message, count: 50)
        await measureRTT(label: "rttSmall", payload: Data(repeating: 0x61, count: 120), count: 30)
        await measureBulk(label: "bulk1KBx256", frameSize: 1024, count: 256)
        await measureBulk(label: "bulk16KBx64", frameSize: 16 * 1024, count: 64)

        log("soak: 1 Hz pings for \(soakSeconds)s (background either app now)")
        var ok = 0, lost = 0
        for i in 0..<soakSeconds {
            let tick = CACurrentMediaTime()
            let result = await ping(payload: message, timeout: 2.5)
            let mine = await currentAppState()
            if let (rtt, peerActive) = result {
                ok += 1
                log(String(format: "soak %03d rtt=%.1fms me=%@ peer=%@", i, rtt, mine, peerActive ? "active" : "background"))
            } else {
                lost += 1
                log(String(format: "soak %03d LOST me=%@ connected=%@", i, mine, await isConnected() ? "yes" : "no"))
            }
            let spent = CACurrentMediaTime() - tick
            if spent < 1 { try? await Task.sleep(nanoseconds: UInt64((1 - spent) * 1_000_000_000)) }
        }
        queue.async {
            self.summary["soak"] = ["ok": ok, "lost": lost, "seconds": soakSeconds]
            self.log("DONE soak ok=\(ok) lost=\(lost)")
        }
    }

    private func measureRTT(label: String, payload: Data, count: Int) async {
        var samples: [Double] = []
        var lost = 0
        for _ in 0..<count {
            if let (rtt, _) = await ping(payload: payload, timeout: 5) { samples.append(rtt) } else { lost += 1 }
        }
        let stats = Self.stats(samples)
        queue.async {
            self.summary[label] = stats.merging(["frameBytes": payload.count + 10, "lost": lost]) { a, _ in a }
            self.log("\(label) payload=\(payload.count)B \(Self.describe(stats)) lost=\(lost)")
        }
    }

    private func measureBulk(label: String, frameSize: Int, count: Int) async {
        let result: (Double, UInt32, UInt64)? = await withCheckedContinuation { cont in
            queue.async {
                guard let stream = self.stream else { cont.resume(returning: nil); return }
                var done = false
                let start = CACurrentMediaTime()
                let body = Data(repeating: 0x42, count: frameSize)
                let seq = self.nextSeq
                self.nextSeq += 1
                self.bulkAck = { _, bytes, rx in
                    guard !done else { return }
                    done = true
                    _ = bytes
                    cont.resume(returning: (rx - start, 0, bytes))
                }
                self.queue.asyncAfter(deadline: .now() + 120) {
                    guard !done else { return }
                    done = true
                    self.bulkAck = nil
                    cont.resume(returning: nil)
                }
                for i in 0..<count {
                    var payload = Self.header(.bulk, UInt32(i))
                    payload.append(body)
                    stream.send(PeerNetworkFrame(kind: .data, payload: payload))
                }
                stream.send(PeerNetworkFrame(kind: .data, payload: Self.header(.bulkEnd, seq)))
            }
        }
        queue.async {
            guard let (seconds, _, bytes) = result else {
                self.log("\(label) timed out")
                return
            }
            let kbps = Double(bytes) * 8 / 1000 / seconds
            self.summary[label] = ["bytes": bytes, "seconds": seconds, "kbps": (kbps * 10).rounded() / 10]
            self.log(String(format: "%@ %llu bytes in %.2fs = %.0f kbit/s (app payload, incl. ack RTT)",
                label, bytes, seconds, kbps))
        }
    }

    private func ping(payload: Data, timeout: Double) async -> (Double, Bool)? {
        await withCheckedContinuation { cont in
            queue.async {
                guard let stream = self.stream else { cont.resume(returning: nil); return }
                let seq = self.nextSeq
                self.nextSeq += 1
                var done = false
                let sent = CACurrentMediaTime()
                self.pending[seq] = { rx, body in
                    guard !done else { return }
                    done = true
                    cont.resume(returning: ((rx - sent) * 1000, body.first == 1))
                }
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    guard !done else { return }
                    done = true
                    self.pending[seq] = nil
                    cont.resume(returning: nil)
                }
                var frame = Self.header(.ping, seq)
                frame.append(payload)
                stream.send(PeerNetworkFrame(kind: .data, payload: frame))
            }
        }
    }

    private func handleCentralFrame(op: SpikeOp, seq: UInt32, body: Data) {
        let rx = CACurrentMediaTime()
        switch op {
        case .pong:
            pending.removeValue(forKey: seq)?(rx, body)
        case .bulkAck:
            let bytes = body.dropFirst(4).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            bulkAck?(seq, bytes, rx)
            bulkAck = nil
        default:
            break
        }
    }

    private func waitForChannel(timeout: Double) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                if self.stream != nil { cont.resume(); return }
                var done = false
                self.channelWaiter = { if !done { done = true; cont.resume() } }
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    if !done { done = true; self.channelWaiter = nil; cont.resume() }
                }
            }
        }
    }

    private func isConnected() async -> Bool {
        await withCheckedContinuation { cont in queue.async { cont.resume(returning: self.stream != nil) } }
    }

    private func currentAppState() async -> String {
        await withCheckedContinuation { cont in queue.async { cont.resume(returning: self.appState) } }
    }

    // MARK: Shared

    private func attach(_ channel: CBL2CAPChannel) {
        stream?.close()
        let stream = BLEL2CAPChannelStream(channel: channel, callbackQueue: queue)
        stream.onFrame = { [weak self] frame in
            guard let self = self, frame.kind == .data, frame.payload.count >= 5,
                let op = SpikeOp(rawValue: frame.payload[frame.payload.startIndex]) else { return }
            let seq = frame.payload.dropFirst().prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            let body = Data(frame.payload.dropFirst(5))
            if self.role == "central" {
                self.handleCentralFrame(op: op, seq: seq, body: body)
            } else {
                self.handlePeripheralFrame(op: op, seq: seq, body: body)
            }
        }
        stream.onClose = { [weak self, weak stream] reason in
            guard let self = self else { return }
            self.log("L2CAP stream closed: \(reason) (appState=\(self.appState))")
            if self.stream === stream { self.stream = nil }
            if self.role == "central", reason != .localCancel { self.handleCentralDrop() }
        }
        self.stream = stream
        stream.open()
    }

    private func log(_ message: String, key: String? = nil, value: Any? = nil) {
        let t = CACurrentMediaTime() - launchTime
        let line = String(format: "%8.3f ", t) + message
        print("[BLESpike] \(line)")
        lines.append(line)
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }
        events.append(["t": (t * 1000).rounded() / 1000, "msg": message])
        if let key = key { summary[key] = value ?? t }
        writeResults()
        let text = lines.suffix(200).joined(separator: "\n")
        DispatchQueue.main.async { self.logText = text }
    }

    private func writeResults() {
        guard let role = summary["role"] as? String,
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let object: [String: Any] = ["summary": summary, "events": events]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("ble-spike-\(role).json"), options: .atomic)
        }
    }

    // MARK: Helpers

    /// A `textMessage` shaped like Hermes's `PeerMessage` (JSON, payload base64), padded to ~targetBytes.
    static func samplePeerMessageJSON(targetBytes: Int) -> Data {
        struct TextPayload: Codable { let messageId: UUID; let originalText: String; let translatedText: String }
        struct Message: Codable { let id: UUID; let type: String; let senderLanguageId: String; let timestamp: Date; let payload: Data }
        var length = 100
        while true {
            let text = String(repeating: "Hola, ¿dónde está la estación? ", count: length / 30 + 1)
            let payload = try! JSONEncoder().encode(TextPayload(messageId: UUID(),
                originalText: String(text.prefix(length)), translatedText: String(text.prefix(length))))
            let data = try! JSONEncoder().encode(Message(id: UUID(), type: "textMessage",
                senderLanguageId: "es-ES", timestamp: Date(), payload: payload))
            if data.count >= targetBytes { return data }
            length += 10
        }
    }

    static func header(_ op: SpikeOp, _ seq: UInt32) -> Data {
        var data = Data([op.rawValue])
        data.append(contentsOf: bytes(seq))
        return data
    }

    static func bytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }

    static func ms(_ seconds: CFTimeInterval) -> Int { Int((seconds * 1000).rounded()) }

    static func stats(_ samples: [Double]) -> [String: Any] {
        guard !samples.isEmpty else { return ["n": 0] }
        let sorted = samples.sorted()
        func pct(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))] }
        func r(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        return ["n": sorted.count, "minMs": r(sorted[0]), "medianMs": r(pct(0.5)), "p95Ms": r(pct(0.95)),
                "maxMs": r(sorted[sorted.count - 1]), "meanMs": r(sorted.reduce(0, +) / Double(sorted.count))]
    }

    static func describe(_ stats: [String: Any]) -> String {
        ["n", "minMs", "medianMs", "p95Ms", "maxMs", "meanMs"].map { "\($0)=\(stats[$0] ?? "-")" }.joined(separator: " ")
    }

    static func modelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
