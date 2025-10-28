import Foundation
import CoreBluetooth
import Combine

@MainActor
final class BLEHeartRateManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // Published state
    @Published private(set) var devices: [CBPeripheral] = []
    @Published private(set) var selectedPeripheral: CBPeripheral?
    @Published private(set) var heartRate: Int?
    @Published private(set) var isScanning: Bool = false

    // Authorization (macOS 12+)
    var isAuthorized: Bool {
        if #available(macOS 12.0, *) {
            return CBCentralManager.authorization == .allowedAlways
        } else {
            // Prior to macOS 12 there is no explicit authorization API
            return true
        }
    }

    // CoreBluetooth
    private var central: CBCentralManager!
    private var peripheralsByID: [UUID: CBPeripheral] = [:]

    // UUIDs
    private let heartRateService = CBUUID(string: "180D")
    private let heartRateMeasurement = CBUUID(string: "2A37")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Scan Control Helpers
    private func restartScan(after delay: TimeInterval = 0.6) {
        // Stop current scan and clear caches, then restart after a small delay to avoid CoreBluetooth races
        stopScan()
        peripheralsByID.removeAll()
        devices.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startScan()
        }
    }

    // MARK: - Public API
    func startScan() {
        if #available(macOS 12.0, *) {
            let auth = CBCentralManager.authorization
            guard auth == .allowedAlways || auth == .notDetermined else { return }
        }
        guard central.state == .poweredOn else { return }

        if !isScanning {
            isScanning = true
            peripheralsByID.removeAll()
            devices.removeAll()
        }

        central.stopScan()
        central.scanForPeripherals(withServices: [heartRateService], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScan() {
        if isScanning {
            central.stopScan()
            isScanning = false
        }
    }

    func selectPeripheral(_ peripheral: CBPeripheral) {
        // Use the central's reference if available
        let target = peripheralsByID[peripheral.identifier] ?? peripheral
        // Disconnect previous
        if let current = selectedPeripheral {
            central.cancelPeripheralConnection(current)
        }
        selectedPeripheral = target
        heartRate = nil
        stopScan()
        target.delegate = self
        central.connect(target, options: nil)
    }

    func disconnect() {
        if let current = selectedPeripheral {
            // Clear state and cancel connection; rely on delegate callback to resume scanning
            current.delegate = nil
            heartRate = nil
            central.cancelPeripheralConnection(current)
        } else {
            // No active connection; restart scanning with a tiny delay to avoid races
            heartRate = nil
            restartScan(after: 0.1)
        }
    }

    /// Hard reset the CoreBluetooth central session (use sparingly)
    func hardResetBluetoothSession() {
        stopScan()
        if let current = selectedPeripheral {
            central.cancelPeripheralConnection(current)
        }
        selectedPeripheral = nil
        heartRate = nil
        peripheralsByID.removeAll()
        devices.removeAll()
        // Recreate central after a small delay to ensure teardown
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // Auto resume scanning if user expects it or after reset
            startScan()
        default:
            stopScan()
            devices.removeAll()
            peripheralsByID.removeAll()
            heartRate = nil
            selectedPeripheral = nil
        }
        // On macOS 12+, if authorization is not determined, a scan request triggers the prompt.
        if #available(macOS 12.0, *) {
            if CBCentralManager.authorization == .notDetermined {
                // Attempt a very short scan to surface the prompt
                central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.central.stopScan()
                }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        let resolved = peripheralsByID[id] ?? peripheral
        peripheralsByID[id] = resolved
        devices = peripheralsByID.values.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Connection established; ensure scanning is stopped to keep state consistent
        stopScan()
        peripheral.discoverServices([heartRateService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if selectedPeripheral == peripheral { selectedPeripheral = nil }
        heartRate = nil
        hardResetBluetoothSession()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if selectedPeripheral == peripheral { selectedPeripheral = nil }
        heartRate = nil
        hardResetBluetoothSession()
    }

    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == heartRateService {
            peripheral.discoverCharacteristics([heartRateMeasurement], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        guard let chars = service.characteristics else { return }
        for c in chars where c.uuid == heartRateMeasurement {
            peripheral.setNotifyValue(true, for: c)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }
        guard characteristic.uuid == heartRateMeasurement, let data = characteristic.value else { return }
        heartRate = Self.parseHeartRate(from: data)
    }

    // MARK: - Parser
    private static func parseHeartRate(from data: Data) -> Int? {
        var bytes = [UInt8](data)
        guard !bytes.isEmpty else { return nil }
        let flags = bytes.removeFirst()
        let isUInt16 = (flags & 0x01) != 0
        if isUInt16 {
            guard bytes.count >= 2 else { return nil }
            let value = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            return Int(value)
        } else {
            guard let first = bytes.first else { return nil }
            return Int(first)
        }
    }
}
