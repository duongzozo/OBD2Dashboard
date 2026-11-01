import CoreBluetooth

/// Configuration for a `BLETransport`, sourced from `AppSettings` so the
/// service/characteristic UUIDs and write type can be corrected from
/// Settings the moment the real adapter's values are known — no code
/// change, no rebuild.
struct BLEAdapterConfig {
    var serviceUUID: CBUUID
    var writeCharacteristicUUID: CBUUID
    var notifyCharacteristicUUID: CBUUID
    var writeType: CBCharacteristicWriteType

    init(settings: AppSettings) {
        serviceUUID = CBUUID(string: settings.bleServiceUUID)
        writeCharacteristicUUID = CBUUID(string: settings.bleWriteCharacteristicUUID)
        notifyCharacteristicUUID = CBUUID(string: settings.bleNotifyCharacteristicUUID)
        writeType = settings.bleWriteType == .withResponse ? .withResponse : .withoutResponse
    }
}

/// CoreBluetooth-backed `BluetoothTransport`. Only ever reports transport-
/// level states (disconnected/scanning/connecting/connected/error) —
/// `.initializing`/`.ecuReady` are added on top by `BluetoothManager` once
/// the ELM327 init sequence runs over this link.
///
/// Classic Bluetooth SPP adapters are explicitly out of scope here: per
/// spec §2, SPP is not reachable via CoreBluetooth at all and would need a
/// separate ExternalAccessory/MFi-backed `BluetoothTransport` conformer.
///
/// CoreBluetooth delegate callbacks fire on the dispatch queue given to
/// `CBCentralManager` below — a background queue, per spec §11 ("Xử lý
/// Bluetooth trên background queue"). Every `state`/`onDiscovered` update
/// that the UI observes is explicitly hopped back to the main queue here
/// ("Cập nhật UI trên main thread"); the connect-timeout `Timer` is always
/// created/invalidated on the main run loop for the same reason — `Timer`
/// isn't safe to invalidate from a thread other than the one that
/// scheduled it.
final class BLETransport: NSObject, BluetoothTransport {
    let state = Observable<ConnectionState>(.disconnected)
    var onDataReceived: ((Data) -> Void)?

    private let config: BLEAdapterConfig
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var targetPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var onDiscovered: ((DiscoveredPeripheral) -> Void)?
    private var connectTimeoutTimer: Timer?
    private var hasRetriedConnect = false

    init(config: BLEAdapterConfig) {
        self.config = config
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue(label: "com.diy.obd2dashboard.ble"))
    }

    private func setState(_ newState: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.state.value = newState
        }
    }

    // TEMPORARY diagnostic logging — no Mac/Xcode console available while
    // debugging why scans return zero results on the real device. Writes
    // to a plain file so results can be inspected over SSH. Remove once
    // the root cause is confirmed fixed.
    private func debugLog(_ message: String) {
        let line = "\(Date()): \(message)\n"
        let path = "/var/mobile/Documents/ble_debug.log"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path), let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    func startScan(onDiscovered: @escaping (DiscoveredPeripheral) -> Void) {
        self.onDiscovered = onDiscovered
        discoveredPeripherals.removeAll()
        debugLog("startScan called, centralManager.state=\(centralManager.state.rawValue)")
        guard centralManager.state == .poweredOn else {
            setState(.error("Bluetooth is off or unavailable"))
            return
        }
        setState(.scanning)
        // Unfiltered scan so the Connection screen can list any nearby BLE
        // device by name — useful while the exact service UUID is still
        // being confirmed against the real adapter.
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    func stopScan() {
        centralManager.stopScan()
    }

    func connect(to peripheralID: String) {
        guard let peripheral = discoveredPeripherals[peripheralID] else {
            setState(.error("Unknown peripheral — scan again"))
            return
        }
        stopScan()
        hasRetriedConnect = false
        attemptConnect(peripheral)
    }

    private func attemptConnect(_ peripheral: CBPeripheral) {
        targetPeripheral = peripheral
        setState(.connecting)
        centralManager.connect(peripheral, options: nil)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectTimeoutTimer?.invalidate()
            self.connectTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
                self?.handleConnectTimeout()
            }
        }
    }

    private func invalidateConnectTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.connectTimeoutTimer?.invalidate()
            self?.connectTimeoutTimer = nil
        }
    }

    private func handleConnectTimeout() {
        guard let peripheral = targetPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
        if !hasRetriedConnect {
            hasRetriedConnect = true
            attemptConnect(peripheral)
        } else {
            setState(.error("Connection timed out"))
        }
    }

    func disconnect() {
        invalidateConnectTimer()
        if let peripheral = targetPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        targetPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        setState(.disconnected)
    }

    func send(_ data: Data) {
        guard let peripheral = targetPeripheral, let characteristic = writeCharacteristic else { return }
        peripheral.writeValue(data, for: characteristic, type: config.writeType)
    }
}

extension BLETransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        debugLog("centralManagerDidUpdateState: \(central.state.rawValue)")
        if central.state != .poweredOn, state.value == .scanning {
            setState(.error("Bluetooth turned off while scanning"))
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        debugLog("didDiscover: \(peripheral.name ?? "nil") id=\(peripheral.identifier) rssi=\(RSSI)")
        let id = peripheral.identifier.uuidString
        discoveredPeripherals[id] = peripheral
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown device"
        let device = DiscoveredPeripheral(id: id, name: name, signalStrength: RSSI.intValue)
        let callback = onDiscovered
        DispatchQueue.main.async {
            callback?(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        invalidateConnectTimer()
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        invalidateConnectTimer()
        setState(.error("Failed to connect: \(error?.localizedDescription ?? "unknown error")"))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        writeCharacteristic = nil
        notifyCharacteristic = nil
        if let error = error {
            setState(.error("Disconnected: \(error.localizedDescription)"))
        } else {
            setState(.disconnected)
        }
    }
}

extension BLETransport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            setState(.error("No services found on adapter"))
            return
        }
        guard let targetService = services.first(where: { $0.uuid == config.serviceUUID }) else {
            setState(.error("Configured service UUID \(config.serviceUUID) not found on this device — check Settings against your adapter's real UUID"))
            return
        }
        peripheral.discoverCharacteristics(nil, for: targetService)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else {
            setState(.error("No characteristics found for configured service"))
            return
        }
        writeCharacteristic = characteristics.first(where: { $0.uuid == config.writeCharacteristicUUID })
        notifyCharacteristic = characteristics.first(where: { $0.uuid == config.notifyCharacteristicUUID })

        guard let notifyCharacteristic = notifyCharacteristic else {
            setState(.error("Configured notify characteristic UUID not found — check Settings"))
            return
        }
        guard writeCharacteristic != nil else {
            setState(.error("Configured write characteristic UUID not found — check Settings"))
            return
        }
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
        setState(.connected)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == config.notifyCharacteristicUUID, let data = characteristic.value else { return }
        onDataReceived?(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            setState(.error("Write failed: \(error.localizedDescription)"))
        }
    }
}
