//
//  BLEL2CAPAdvertiser.swift
//  PeerConnectivity
//
//  SPIKE: feasibility prototype for a Bluetooth LE L2CAP transport. Internal only.
//

#if canImport(CoreBluetooth)
import CoreBluetooth
import Foundation

internal enum BLEL2CAPService {
    /// Primary service a Hermes peer advertises. Spike value; a real transport would derive it
    /// from the `ServiceType` so separate apps never discover each other.
    static let serviceUUID = CBUUID(string: "6E3A0001-8F3C-4B8E-9D2A-48E5A7C1B001")
    /// Read-only characteristic whose value is the published PSM as a 2-byte big-endian integer.
    /// iOS cannot put arbitrary data in an advertisement, so the PSM travels over GATT.
    static let psmCharacteristicUUID = CBUUID(string: "6E3A0002-8F3C-4B8E-9D2A-48E5A7C1B001")
}

/// Peripheral side: publishes an L2CAP channel, exposes its PSM over GATT and advertises the
/// service UUID. Every incoming channel is handed to `onChannel`.
internal final class BLEL2CAPAdvertiser : NSObject, CBPeripheralManagerDelegate {

    internal enum Event {
        case stateChanged(CBManagerState)
        case published(psm: CBL2CAPPSM)
        case advertisingStarted(Error?)
        case channelOpened(CBL2CAPChannel)
        case channelFailed(Error)
    }

    internal var onEvent : ((Event) -> Void)?

    fileprivate let queue : DispatchQueue
    fileprivate let localName : String
    fileprivate let requireEncryption : Bool
    fileprivate var manager : CBPeripheralManager!
    fileprivate var psm : CBL2CAPPSM?
    fileprivate var openChannels : [CBL2CAPChannel] = []

    /// - parameter requireEncryption: `true` makes CoreBluetooth demand an encrypted (paired)
    ///   link before the channel opens, which shows the system pairing prompt.
    internal init(localName: String, requireEncryption: Bool = false, queue: DispatchQueue) {
        self.localName = localName
        self.requireEncryption = requireEncryption
        self.queue = queue
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: queue, options: [
            CBPeripheralManagerOptionShowPowerAlertKey: true
        ])
    }

    internal func stop() {
        manager.stopAdvertising()
        if let psm = psm { manager.unpublishL2CAPChannel(psm) }
        manager.removeAllServices()
        openChannels.removeAll()
    }

    // MARK: CBPeripheralManagerDelegate

    internal func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        onEvent?(.stateChanged(peripheral.state))
        guard peripheral.state == .poweredOn else { return }
        peripheral.publishL2CAPChannel(withEncryption: requireEncryption)
    }

    internal func peripheralManager(_ peripheral: CBPeripheralManager,
        didPublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?) {
        if let error = error {
            onEvent?(.channelFailed(error))
            return
        }
        psm = PSM
        onEvent?(.published(psm: PSM))

        let characteristic = CBMutableCharacteristic(
            type: BLEL2CAPService.psmCharacteristicUUID,
            properties: [.read],
            value: Data([UInt8(PSM >> 8), UInt8(PSM & 0xff)]),
            permissions: [.readable])
        let service = CBMutableService(type: BLEL2CAPService.serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheral.add(service)
    }

    internal func peripheralManager(_ peripheral: CBPeripheralManager,
        didAdd service: CBService, error: Error?) {
        if let error = error {
            onEvent?(.advertisingStarted(error))
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEL2CAPService.serviceUUID],
            CBAdvertisementDataLocalNameKey: localName
        ])
    }

    internal func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        onEvent?(.advertisingStarted(error))
    }

    internal func peripheralManager(_ peripheral: CBPeripheralManager,
        didOpen channel: CBL2CAPChannel?, error: Error?) {
        if let error = error {
            onEvent?(.channelFailed(error))
            return
        }
        guard let channel = channel else { return }
        // CoreBluetooth closes a channel whose last strong reference goes away.
        openChannels.append(channel)
        onEvent?(.channelOpened(channel))
    }
}
#endif
