import Foundation
import CoreBluetooth

// Standard Bluetooth SIG services some scales implement.
private let weightScaleServiceUUID        = CBUUID(string: "181D")
private let weightMeasurementCharUUID      = CBUUID(string: "2A9D")
private let bodyCompositionServiceUUID     = CBUUID(string: "181B")
private let bodyCompositionMeasurementUUID = CBUUID(string: "2A9C")

struct ScaleReading: Identifiable {
    let id = UUID()
    let date: Date
    let weightKg: Double
    let stable: Bool
    let source: String   // which characteristic / decoder produced this
}

final class BLEScaleManager: NSObject, ObservableObject {
    @Published var status: String = "Idle"
    @Published var bluetoothReady = false
    @Published var scanning = false
    @Published var discovered: [CBPeripheral] = []
    @Published var connectedName: String?
    @Published var latest: ScaleReading?
    @Published var history: [ScaleReading] = []
    @Published var rawLog: [String] = []   // hex dumps for reverse-engineering unknown scales

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var seen = Set<UUID>()

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else {
            status = "Bluetooth not ready"
            return
        }
        discovered.removeAll()
        seen.removeAll()
        scanning = true
        status = "Scanning for scales..."
        // Pass nil: many budget scales do not advertise the standard service,
        // so we discover everything and let you pick, then log what it sends.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
        scanning = false
        if status.hasPrefix("Scanning") { status = "Scan stopped" }
    }

    func connect(_ p: CBPeripheral) {
        stopScan()
        peripheral = p
        p.delegate = self
        status = "Connecting to \(p.name ?? "device")..."
        central.connect(p, options: nil)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    private func log(_ s: String) {
        let t = Date().formatted(date: .omitted, time: .standard)
        DispatchQueue.main.async {
            self.rawLog.insert("\(t)  \(s)", at: 0)
            if self.rawLog.count > 300 { self.rawLog.removeLast() }
        }
    }

    // MARK: - Decoders

    // Standard SIG Weight Measurement (0x2A9D). Correct per Bluetooth spec.
    private func decodeStandardWeight(_ data: Data) -> ScaleReading? {
        let b = [UInt8](data)
        guard b.count >= 3 else { return nil }
        let flags = b[0]
        let imperial = (flags & 0x01) != 0
        let raw = UInt16(b[1]) | (UInt16(b[2]) << 8)
        let kg: Double = imperial
            ? Double(raw) * 0.01 * 0.45359237   // lb -> kg
            : Double(raw) * 0.005               // SI resolution
        return ScaleReading(date: Date(), weightKg: kg, stable: true, source: "SIG 2A9D")
    }

    // Plug your scale's custom format in here once we read its raw bytes.
    // Many Lefu/OKOK scales notify a stream of frames where a stable reading
    // is flagged in a status byte and weight is a big- or little-endian uint16
    // at a fixed offset, scaled by 0.01 or 0.1. We confirm the exact layout
    // from the rawLog, then fill this in. Returns nil until then.
    private func decodeCustom(_ data: Data, char: CBUUID) -> ScaleReading? {
        return nil
    }

    private func handle(_ data: Data, char: CBUUID) {
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        log("\(char.uuidString): \(hex)")

        if let r = decodeStandardWeight(data), char == weightMeasurementCharUUID {
            publish(r); return
        }
        if let r = decodeCustom(data, char: char) {
            publish(r); return
        }
    }

    private func publish(_ r: ScaleReading) {
        DispatchQueue.main.async {
            self.latest = r
            if r.stable { self.history.insert(r, at: 0) }
        }
    }
}

extension BLEScaleManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        bluetoothReady = c.state == .poweredOn
        switch c.state {
        case .poweredOn:   status = "Ready"
        case .poweredOff:  status = "Bluetooth is off"
        case .unauthorized: status = "Bluetooth permission denied"
        default:           status = "Bluetooth unavailable"
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = p.name, !name.isEmpty else { return }  // skip unnamed noise
        if !seen.contains(p.identifier) {
            seen.insert(p.identifier)
            DispatchQueue.main.async { self.discovered.append(p) }
            // Log any manufacturer/service data: some scales ship weight in the advert itself.
            if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
                let hex = mfg.map { String(format: "%02X", $0) }.joined(separator: " ")
                log("ADV \(name) mfgData: \(hex)")
            }
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        connectedName = p.name
        status = "Connected. Discovering services..."
        p.discoverServices(nil)
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        connectedName = nil
        status = "Disconnected"
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        status = "Failed to connect: \(error?.localizedDescription ?? "unknown")"
    }
}

extension BLEScaleManager: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] {
            log("Service \(s.uuid.uuidString)")
            p.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            log("  Char \(ch.uuid.uuidString) props \(ch.properties.rawValue)")
            if ch.properties.contains(.notify) || ch.properties.contains(.indicate) {
                p.setNotifyValue(true, for: ch)
            } else if ch.properties.contains(.read) {
                p.readValue(for: ch)
            }
        }
        status = "Subscribed. Step on the scale."
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let data = ch.value else { return }
        handle(data, char: ch.uuid)
    }
}
