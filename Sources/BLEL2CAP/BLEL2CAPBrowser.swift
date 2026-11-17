//
//  BLEL2CAPBrowser.swift
//  PeerConnectivity
//
//  SPIKE: feasibility prototype for a Bluetooth LE L2CAP transport. Internal only.
//

#if canImport(CoreBluetooth)
import CoreBluetooth
import Foundation

/// Central side: scans for the Hermes service, connects to the first peer it finds, reads the
/// PSM over GATT and opens the L2CAP channel. Each step is reported so the spike can time it.
internal final class BLEL2CAPBrowser : NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    internal enum Event {
        case stateChanged(CBManagerState)
        case scanStarted
        case discovered(name: String?, rssi: Int)
        case connected
        case servicesDiscovered
        case psmRead(CBL2CAPPSM)
        case channelOpened(CBL2CAPChannel)
        case failed(String)
        case disconnected(Error?)
    }

    internal var onEvent : ((Event) -> Void)?

    fileprivate let queue : DispatchQueue
    fileprivate var manager : CBCentralManager!
    fileprivate var peripheral : CBPeripheral?
    fileprivate var channel : CBL2CAPChannel?

    internal init(queue: DispatchQueue) {
        self.queue = queue
        super.init()
        manager = CBCentralManager(delegate: self, queue: queue, options: [
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
    }

    internal func stop() {
        manager.stopScan()
        if let peripheral = peripheral { manager.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        channel = nil
    }

    // MARK: CBCentralManagerDelegate

    internal func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onEvent?(.stateChanged(central.state))
        guard central.state == .poweredOn, peripheral == nil else { return }
        central.scanForPeripherals(withServices: [BLEL2CAPService.serviceUUID], options: nil)
        onEvent?(.scanStarted)
    }

    internal func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        onEvent?(.discovered(name: name, rssi: RSSI.intValue))
        central.connect(peripheral, options: nil)
    }

    internal func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onEvent?(.connected)
        peripheral.discoverServices([BLEL2CAPService.serviceUUID])
    }

    internal func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
        error: Error?) {
        onEvent?(.failed("connect: \(error.map { String(describing: $0) } ?? "unknown")"))
    }

    internal func centralManager(_ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onEvent?(.disconnected(error))
    }

    // MARK: CBPeripheralDelegate

    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
            let service = peripheral.services?.first(where: { $0.uuid == BLEL2CAPService.serviceUUID }) else {
            onEvent?(.failed("services: \(error.map { String(describing: $0) } ?? "service missing")"))
            return
        }
        onEvent?(.servicesDiscovered)
        peripheral.discoverCharacteristics([BLEL2CAPService.psmCharacteristicUUID], for: service)
    }

    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
        error: Error?) {
        guard error == nil,
            let characteristic = service.characteristics?.first(where: {
                $0.uuid == BLEL2CAPService.psmCharacteristicUUID
            }) else {
            onEvent?(.failed("characteristics: \(error.map { String(describing: $0) } ?? "PSM missing")"))
            return
        }
        peripheral.readValue(for: characteristic)
    }

    internal func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?) {
        guard error == nil, let value = characteristic.value, value.count == 2 else {
            onEvent?(.failed("PSM read: \(error.map { String(describing: $0) } ?? "bad value")"))
            return
        }
        let psm = CBL2CAPPSM(value[value.startIndex]) << 8 | CBL2CAPPSM(value[value.startIndex + 1])
        onEvent?(.psmRead(psm))
        peripheral.openL2CAPChannel(psm)
    }

    internal func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard error == nil, let channel = channel else {
            onEvent?(.failed("L2CAP open: \(error.map { String(describing: $0) } ?? "no channel")"))
            return
        }
        self.channel = channel
        onEvent?(.channelOpened(channel))
    }
}
#endif
