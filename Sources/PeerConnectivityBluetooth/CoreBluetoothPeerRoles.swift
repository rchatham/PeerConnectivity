//
//  CoreBluetoothPeerRoles.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 11/18/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import CoreBluetooth
import PeerConnectivity

/// Publishes the PeerConnectivity service and an L2CAP channel, and advertises when asked.
///
/// The channel is published without BLE link encryption: `BluetoothSecureChannel` provides the
/// security the app chose, and an encrypted link would make iOS show a pairing prompt.
/// All state is confined to `queue`, where Core Bluetooth delivers every callback.
@available(iOS 13.0, macOS 10.15, *)
internal final class CoreBluetoothPeerPeripheral : NSObject, BluetoothPeerAdvertising {

    fileprivate let serviceUUID : CBUUID
    fileprivate let identityPayload : Data
    fileprivate let handlers : BluetoothPeerAdvertisingHandlers
    fileprivate let queue = DispatchQueue(label: "PeerConnectivity.CoreBluetoothPeerPeripheral")
    fileprivate var manager : CBPeripheralManager?
    fileprivate var publishedPSM : CBL2CAPPSM?
    fileprivate var isServiceAdded = false
    fileprivate var wantsAdvertising = false

    internal init(serviceUUID: CBUUID, identityPayload: Data, handlers: BluetoothPeerAdvertisingHandlers) {
        self.serviceUUID = serviceUUID
        self.identityPayload = identityPayload
        self.handlers = handlers
        super.init()
    }

    internal func start() {
        queue.async { [self] in
            guard manager == nil else { return }
            manager = CBPeripheralManager(delegate: self, queue: queue)
        }
    }

    internal func cancel() {
        queue.async { [self] in
            guard let manager = manager else { return }
            if manager.isAdvertising {
                manager.stopAdvertising()
            }
            manager.removeAllServices()
            if let psm = publishedPSM {
                manager.unpublishL2CAPChannel(psm)
            }
            manager.delegate = nil
            self.manager = nil
            publishedPSM = nil
            isServiceAdded = false
        }
    }

    internal func setAdvertising(_ isAdvertising: Bool) {
        queue.async { [self] in
            wantsAdvertising = isAdvertising
            updateAdvertising()
        }
    }

    fileprivate func updateAdvertising() {
        guard let manager = manager, isServiceAdded else { return }
        if wantsAdvertising && !manager.isAdvertising {
            manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID]])
        } else if !wantsAdvertising && manager.isAdvertising {
            manager.stopAdvertising()
        }
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension CoreBluetoothPeerPeripheral : CBPeripheralManagerDelegate {

    internal func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            guard publishedPSM == nil else { return }
            peripheral.publishL2CAPChannel(withEncryption: false)
            return
        }
        // Core Bluetooth drops published services and channels when the radio goes away.
        publishedPSM = nil
        isServiceAdded = false
        if let error = PeerBluetoothError(state: peripheral.state) {
            handlers.failed(.advertisingFailed(underlying: error))
        }
    }

    internal func peripheralManager(_ peripheral: CBPeripheralManager, didPublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?) {
        if let error = error {
            handlers.failed(.advertisingFailed(underlying: error))
            return
        }
        publishedPSM = PSM
        var littleEndianPSM = PSM.littleEndian
        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [
            CBMutableCharacteristic(type: BluetoothPeerService.identityCharacteristicUUID,
                properties: .read, value: identityPayload, permissions: .readable),
            CBMutableCharacteristic(type: BluetoothPeerService.psmCharacteristicUUID,
                properties: .read, value: Data(bytes: &littleEndianPSM, count: MemoryLayout<CBL2CAPPSM>.size),
                permissions: .readable),
        ]
        peripheral.add(service)
    }

    internal func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            handlers.failed(.advertisingFailed(underlying: error))
            return
        }
        isServiceAdded = true
        updateAdvertising()
    }

    internal func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            handlers.failed(.advertisingFailed(underlying: error))
        }
    }

    internal func peripheralManager(_ peripheral: CBPeripheralManager, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard error == nil, let channel = channel,
            let inputStream = channel.inputStream, let outputStream = channel.outputStream else { return }
        handlers.channelOpened(BluetoothChannelStreams(inputStream: inputStream, outputStream: outputStream, owner: channel))
    }
}

/// Scans for the PeerConnectivity service, reads each new peer's identity once, and opens
/// L2CAP channels on request.
///
/// Reading the identity needs a brief connection, which is dropped afterwards so idle peers do
/// not hold radio links; an invitation reconnects. Scanning allows duplicates so every
/// advertisement counts as a sighting for lost-peer expiry (foreground only; iOS coalesces
/// duplicates in the background). All state is confined to `queue`.
@available(iOS 13.0, macOS 10.15, *)
internal final class CoreBluetoothPeerCentral : NSObject, BluetoothPeerScanning {

    /// Bounds on what nearby advertisers can make this device hold or do. Addresses rotate, so
    /// one device (or an attacker cycling addresses) can appear as many peripherals.
    internal struct Limits {
        internal var maxKnownPeripherals = 128
        internal var maxPendingReads = 4
        internal var readTimeout : TimeInterval = 10
    }

    fileprivate let serviceUUID : CBUUID
    fileprivate let handlers : BluetoothPeerScanningHandlers
    fileprivate let limits : Limits
    fileprivate let queue = DispatchQueue(label: "PeerConnectivity.CoreBluetoothPeerCentral")
    fileprivate var manager : CBCentralManager?
    fileprivate var wantsScanning = false
    /// Retained while known: Core Bluetooth does not keep discovered peripherals alive.
    fileprivate var peripherals : [UUID:CBPeripheral] = [:]
    fileprivate var lastSeen : [UUID:Date] = [:]
    fileprivate var identities : [UUID:PeerNetworkDiscoveryInfo] = [:]
    fileprivate var psms : [UUID:CBL2CAPPSM] = [:]
    fileprivate var pendingReads : Set<UUID> = []
    fileprivate var channelRequests : Set<UUID> = []

    internal init(serviceUUID: CBUUID, handlers: BluetoothPeerScanningHandlers, limits: Limits = Limits()) {
        self.serviceUUID = serviceUUID
        self.handlers = handlers
        self.limits = limits
        super.init()
    }

    internal func start() {
        queue.async { [self] in
            wantsScanning = true
            if manager == nil {
                manager = CBCentralManager(delegate: self, queue: queue)
            } else {
                scanIfReady()
            }
        }
    }

    /// Stops scanning and forgets identities. Links already carrying channels stay up, as Network
    /// connections outlive their browser.
    internal func cancel() {
        queue.async { [self] in
            wantsScanning = false
            manager?.stopScan()
            identities.removeAll()
            channelRequests.removeAll()
        }
    }

    internal func openChannel(to peripheral: UUID) {
        queue.async { [self] in
            guard let manager = manager, let target = peripherals[peripheral] else {
                handlers.channelFailed(peripheral, nil)
                return
            }
            channelRequests.insert(peripheral)
            switch target.state {
            case .connected:
                // Without a PSM yet, the reads in flight open the channel when they finish.
                if let psm = psms[peripheral] {
                    target.openL2CAPChannel(psm)
                }
            case .connecting:
                break
            default:
                manager.connect(target)
            }
        }
    }

    fileprivate func scanIfReady() {
        guard wantsScanning, let manager = manager, manager.state == .poweredOn, !manager.isScanning else { return }
        manager.scanForPeripherals(withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    /// Ends a link that failed or was only needed for reading, reporting any pending channel request.
    fileprivate func finish(_ peripheral: CBPeripheral, error: Error?) {
        let identifier = peripheral.identifier
        pendingReads.remove(identifier)
        if channelRequests.remove(identifier) != nil {
            handlers.channelFailed(identifier, error)
        }
        if identities[identifier] == nil {
            // Unknown peers are retried on their next advertisement.
            forget(identifier)
        }
    }

    /// Starts reading a new peripheral's identity, within the limits. Returns false when it must wait.
    fileprivate func beginIdentityRead(_ peripheral: CBPeripheral, using central: CBCentralManager) -> Bool {
        guard pendingReads.count < limits.maxPendingReads, makeRoomForPeripheral() else { return false }
        let identifier = peripheral.identifier
        peripherals[identifier] = peripheral
        pendingReads.insert(identifier)
        peripheral.delegate = self
        central.connect(peripheral)
        queue.asyncAfter(deadline: .now() + limits.readTimeout) { [weak self] in
            self?.abandonIdentityRead(identifier)
        }
        return true
    }

    /// A peripheral that accepts the connection but never answers would otherwise hold a slot forever.
    fileprivate func abandonIdentityRead(_ identifier: UUID) {
        guard pendingReads.remove(identifier) != nil, let peripheral = peripherals[identifier] else { return }
        manager?.cancelPeripheralConnection(peripheral)
        if channelRequests.remove(identifier) != nil {
            handlers.channelFailed(identifier, nil)
        }
        forget(identifier)
    }

    /// Evicts the least recently seen idle peripheral when the table is full.
    fileprivate func makeRoomForPeripheral() -> Bool {
        guard peripherals.count >= limits.maxKnownPeripherals else { return true }
        let evictable = peripherals.keys.filter { !pendingReads.contains($0) && !channelRequests.contains($0) }
        guard let oldest = evictable.min(by: { (lastSeen[$0] ?? .distantPast) < (lastSeen[$1] ?? .distantPast) }) else {
            return false
        }
        if let peripheral = peripherals[oldest], peripheral.state != .disconnected {
            manager?.cancelPeripheralConnection(peripheral)
        }
        forget(oldest)
        return true
    }

    fileprivate func forget(_ identifier: UUID) {
        peripherals.removeValue(forKey: identifier)
        lastSeen.removeValue(forKey: identifier)
        identities.removeValue(forKey: identifier)
        psms.removeValue(forKey: identifier)
        pendingReads.remove(identifier)
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension CoreBluetoothPeerCentral : CBCentralManagerDelegate {

    internal func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            scanIfReady()
            return
        }
        identities.removeAll()
        psms.removeAll()
        peripherals.removeAll()
        lastSeen.removeAll()
        pendingReads.removeAll()
        channelRequests.removeAll()
        if let error = PeerBluetoothError(state: central.state) {
            handlers.failed(.browsingFailed(underlying: error))
        }
    }

    internal func centralManager(_ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String:Any],
        rssi RSSI: NSNumber) {
        let identifier = peripheral.identifier
        if peripherals[identifier] != nil {
            lastSeen[identifier] = Date()
        }
        if let info = identities[identifier] {
            handlers.sighted(identifier, info)
            return
        }
        // Identity unknown and no read in flight: connect once to read it, if a slot is free.
        guard peripherals[identifier] == nil, beginIdentityRead(peripheral, using: central) else { return }
        lastSeen[identifier] = Date()
    }

    internal func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceUUID])
    }

    internal func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(peripheral, error: error)
    }

    internal func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        finish(peripheral, error: error)
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension CoreBluetoothPeerCentral : CBPeripheralDelegate {

    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            manager?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([BluetoothPeerService.identityCharacteristicUUID,
            BluetoothPeerService.psmCharacteristicUUID], for: service)
    }

    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        guard error == nil, characteristics.count == 2 else {
            manager?.cancelPeripheralConnection(peripheral)
            return
        }
        characteristics.forEach { peripheral.readValue(for: $0) }
    }

    internal func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let identifier = peripheral.identifier
        guard error == nil, let value = characteristic.value else {
            manager?.cancelPeripheralConnection(peripheral)
            return
        }
        switch characteristic.uuid {
        case BluetoothPeerService.identityCharacteristicUUID:
            guard let info = BluetoothPeerService.discoveryInfo(fromIdentityPayload: value) else {
                manager?.cancelPeripheralConnection(peripheral)
                return
            }
            identities[identifier] = info
            handlers.sighted(identifier, info)
        case BluetoothPeerService.psmCharacteristicUUID:
            guard value.count == MemoryLayout<CBL2CAPPSM>.size else {
                manager?.cancelPeripheralConnection(peripheral)
                return
            }
            psms[identifier] = CBL2CAPPSM(value[value.startIndex]) | CBL2CAPPSM(value[value.startIndex + 1]) << 8
        default:
            return
        }

        guard identities[identifier] != nil, let psm = psms[identifier] else { return }
        pendingReads.remove(identifier)
        if channelRequests.contains(identifier) {
            peripheral.openL2CAPChannel(psm)
        } else {
            manager?.cancelPeripheralConnection(peripheral)
        }
    }

    internal func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        let identifier = peripheral.identifier
        guard channelRequests.remove(identifier) != nil else { return }
        guard error == nil, let channel = channel,
            let inputStream = channel.inputStream, let outputStream = channel.outputStream else {
            handlers.channelFailed(identifier, error)
            return
        }
        handlers.channelOpened(identifier, BluetoothChannelStreams(inputStream: inputStream,
            outputStream: outputStream, owner: channel))
    }
}
