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
    let impedance: Double?   // ohms, when the scale reports it
    let stable: Bool
    let source: String       // which decoder produced this
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
    private var recentWeights: [Double] = []   // for heuristic stability detection

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
        recentWeights.removeAll()
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

    private func u16(_ b: [UInt8], _ i: Int, bigEndian: Bool) -> Int {
        bigEndian ? (Int(b[i]) << 8 | Int(b[i + 1])) : (Int(b[i]) | Int(b[i + 1]) << 8)
    }

    // Standard SIG Weight Measurement (0x2A9D). Correct per Bluetooth spec.
    private func decodeStandardWeight(_ data: Data) -> ScaleReading? {
        let b = [UInt8](data)
        guard b.count >= 3 else { return nil }
        let flags = b[0]
        let imperial = (flags & 0x01) != 0
        let raw = u16(b, 1, bigEndian: false)
        let kg: Double = imperial
            ? Double(raw) * 0.01 * 0.45359237
            : Double(raw) * 0.005
        return ScaleReading(date: Date(), weightKg: kg, impedance: nil, stable: true, source: "SIG 2A9D")
    }

    // Heuristic decoder for custom (non-standard) scales. We don't know the exact byte
    // layout, so we hunt for a uint16 that reads as a plausible body weight and a second
    // uint16 that reads as a plausible impedance, trying both byte orders and common
    // scalings. A reading is marked "stable" once the weight holds steady across frames.
    // This is best-effort; the raw log still captures every byte so the exact layout for
    // a specific model can be locked in via decodeExact() once known.
    private func decodeHeuristic(_ data: Data) -> ScaleReading? {
        let b = [UInt8](data)
        guard b.count >= 2 else { return nil }

        // Find a weight candidate: first uint16 (either endian) that scales into human range.
        let scales: [Double] = [0.01, 0.05, 0.1]
        var weight: Double?
        var wOffset = -1
        search: for i in 0..<(b.count - 1) {
            for be in [false, true] {
                let raw = u16(b, i, bigEndian: be)
                for s in scales {
                    let v = Double(raw) * s
                    if v >= 3 && v <= 300 { weight = v; wOffset = i; break search }
                }
            }
        }
        guard let w = weight else { return nil }

        // Find an impedance candidate: a uint16 in a plausible ohm range, away from the
        // weight bytes.
        var imp: Double?
        for i in 0..<(b.count - 1) where i < wOffset - 1 || i > wOffset + 1 {
            for be in [false, true] {
                let raw = u16(b, i, bigEndian: be)
                if raw >= 150 && raw <= 1000 { imp = Double(raw); break }
            }
            if imp != nil { break }
        }

        // Stability: weight steady (within 0.15 kg) across the last 3 frames.
        recentWeights.append(w)
        if recentWeights.count > 4 { recentWeights.removeFirst() }
        let last3 = recentWeights.suffix(3)
        let stable = last3.count == 3 && (last3.max()! - last3.min()! <= 0.15)

        return ScaleReading(date: Date(), weightKg: w, impedance: imp, stable: stable, source: "heuristic")
    }

    private func handle(_ data: Data, char: CBUUID) {
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        log("\(char.uuidString): \(hex)")

        if char == weightMeasurementCharUUID, let r = decodeStandardWeight(data) {
            publish(r); return
        }
        if let r = decodeHeuristic(data) {
            publish(r); return
        }
    }

    private func publish(_ r: ScaleReading) {
        DispatchQueue.main.async {
            self.latest = r
            if r.stable {
                // Replace a prior unstable tail entry or append the stabilized reading.
                self.history.insert(r, at: 0)
                if self.history.count > 50 { self.history.removeLast() }
            }
            self.status = r.stable ? "Stable reading" : "Reading..."
        }
    }
}

extension BLEScaleManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        bluetoothReady = c.state == .poweredOn
        switch c.state {
        case .poweredOn:    status = "Ready"
        case .poweredOff:   status = "Bluetooth is off"
        case .unauthorized: status = "Bluetooth permission denied"
        default:            status = "Bluetooth unavailable"
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = p.name, !name.isEmpty else { return }
        if !seen.contains(p.identifier) {
            seen.insert(p.identifier)
            DispatchQueue.main.async { self.discovered.append(p) }
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
