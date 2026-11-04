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
/// This is also why Settings.app listing a speaker or TV says nothing
/// about this code path — those are Classic devices and CoreBluetooth is
/// *supposed* to be blind to them.
///
/// CoreBluetooth delegate callbacks fire on `bleQueue` (a background
/// queue, per spec §11 "Xử lý Bluetooth trên background queue"). All
/// mutable state below — `discoveredPeripherals`, `targetPeripheral`,
/// `scanPending`, `transportState` — is confined to that queue, and the
/// public `startScan`/`stopScan`/`connect`/`disconnect`/`send` entry
/// points hop onto it rather than touching that state from the caller's
/// thread. Every `state`/`onDiscovered` update the UI observes is hopped
/// back to main ("Cập nhật UI trên main thread"); the connect-timeout
/// `Timer` is always created/invalidated on the main run loop for the same
/// reason — `Timer` isn't safe to invalidate from a thread other than the
/// one that scheduled it.
final class BLETransport: NSObject, BluetoothTransport {
    let state = Observable<ConnectionState>(.disconnected)
    var onDataReceived: ((Data) -> Void)?

    private let config: BLEAdapterConfig
    private let bleQueue = DispatchQueue(label: "com.diy.obd2dashboard.ble")
    private var centralManager: CBCentralManager!

    // MARK: - bleQueue-confined state
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var targetPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    /// The write type the adapter actually supports, set during discovery.
    private var writeType: CBCharacteristicWriteType = .withoutResponse
    private var onDiscovered: ((DiscoveredPeripheral) -> Void)?
    private var hasRetriedConnect = false
    /// A scan was asked for while the central was not yet `.poweredOn`.
    /// Without this, a scan requested during the ~0.1–1s the central takes
    /// to settle after launch was dropped on the floor permanently: the
    /// previous code reported an error and `centralManagerDidUpdateState`
    /// never restarted anything. `autoReconnectIfEnabled()` lands inside
    /// exactly that window on every cold start.
    private var scanPending = false
    /// Mirror of `state.value` readable from `bleQueue` without racing the
    /// main-queue writes made in `setState`.
    private var transportState: ConnectionState = .disconnected
    /// Bumped whenever a scan starts or stops, so stale heartbeats from a
    /// previous scan silently expire instead of logging forever.
    private var scanGeneration = 0

    private var connectTimeoutTimer: Timer?

    init(config: BLEAdapterConfig) {
        self.config = config
        super.init()
        BLELog.shared.log("BLETransport init — service=\(config.serviceUUID) write=\(config.writeCharacteristicUUID) notify=\(config.notifyCharacteristicUUID)")
        centralManager = CBCentralManager(delegate: self, queue: bleQueue)
        BLELog.shared.log("CBCentralManager created, initial state=\(BLETransport.describe(centralManager.state))")
    }

    /// Human-readable `CBManagerState`. This is the single most diagnostic
    /// value in the whole flow: `.unauthorized`/`.unsupported` points at
    /// the app's signature or the platform, `.poweredOff` at the user, and
    /// `.poweredOn` with zero discoveries points at the adapter or at the
    /// scan itself rather than at permissions.
    private static func describe(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown (not yet determined)"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported (no BLE hardware/stack)"
        case .unauthorized: return "unauthorized (app denied BLE access)"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unrecognised(\(state.rawValue))"
        }
    }

    /// Must run on `bleQueue`.
    private func setState(_ newState: ConnectionState) {
        transportState = newState
        if case .error(let message) = newState {
            BLELog.shared.log("state -> ERROR: \(message)")
        } else {
            BLELog.shared.log("state -> \(newState.shortLabel)")
        }
        DispatchQueue.main.async { [weak self] in
            self?.state.value = newState
        }
    }

    // MARK: - Scanning

    func startScan(onDiscovered: @escaping (DiscoveredPeripheral) -> Void) {
        bleQueue.async { [weak self] in
            guard let self = self else { return }
            self.onDiscovered = onDiscovered
            self.discoveredPeripherals.removeAll()
            self.scanPending = true
            self.startScanIfPowered(trigger: "startScan()")
        }
    }

    /// Must run on `bleQueue`.
    private func startScanIfPowered(trigger: String) {
        let central = centralManager.state
        BLELog.shared.log("scan requested by \(trigger) — central.state=\(BLETransport.describe(central))")

        guard central == .poweredOn else {
            switch central {
            case .unknown, .resetting:
                // Not an error — the central simply hasn't settled yet.
                // `scanPending` stays set so `centralManagerDidUpdateState`
                // starts the scan the moment it powers on.
                BLELog.shared.log("central not settled yet — scan deferred until poweredOn")
                setState(.scanning)
            default:
                scanPending = false
                setState(.error("Bluetooth unavailable: \(BLETransport.describe(central))"))
            }
            return
        }

        scanPending = false
        setState(.scanning)
        // Unfiltered scan so the Connection screen can list any nearby BLE
        // device by name — useful while the exact service UUID is still
        // being confirmed against the real adapter.
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        BLELog.shared.log("scanForPeripherals(withServices: nil) called — isScanning=\(centralManager.isScanning)")

        scanGeneration += 1
        scheduleScanHeartbeat(generation: scanGeneration, elapsed: 0)
    }

    /// Logs scan progress every 5s for the first 30s.
    ///
    /// This is what separates two failure modes that look identical in the
    /// UI. "isScanning=true, discovered=0, t+30s" means the scan really is
    /// running and nothing is answering it — adapter is Classic-SPP, out of
    /// range, asleep, or already bonded to another phone. `isScanning`
    /// flipping to false on its own instead means something tore the scan
    /// down underneath us.
    private func scheduleScanHeartbeat(generation: Int, elapsed: Int) {
        guard elapsed < 30 else { return }
        bleQueue.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, self.scanGeneration == generation else { return }
            let next = elapsed + 5
            BLELog.shared.log("scan heartbeat t+\(next)s — isScanning=\(self.centralManager.isScanning) discovered=\(self.discoveredPeripherals.count) central.state=\(BLETransport.describe(self.centralManager.state))")
            self.scheduleScanHeartbeat(generation: generation, elapsed: next)
        }
    }

    func stopScan() {
        bleQueue.async { [weak self] in
            guard let self = self else { return }
            self.scanPending = false
            self.scanGeneration += 1 // expires any pending heartbeat
            self.centralManager.stopScan()
            BLELog.shared.log("stopScan() — \(self.discoveredPeripherals.count) device(s) discovered this scan")
        }
    }

    // MARK: - Connecting

    func connect(to peripheralID: String) {
        bleQueue.async { [weak self] in
            guard let self = self else { return }
            guard let peripheral = self.discoveredPeripherals[peripheralID] else {
                BLELog.shared.log("connect(to: \(peripheralID)) failed — not in discovered set (have \(self.discoveredPeripherals.count))")
                self.setState(.error("Unknown peripheral — scan again"))
                return
            }
            self.scanPending = false
            self.scanGeneration += 1
            self.centralManager.stopScan()
            self.hasRetriedConnect = false
            BLELog.shared.log("connect(to: \(peripheralID)) — name=\(peripheral.name ?? "nil")")
            self.attemptConnect(peripheral)
        }
    }

    /// Must run on `bleQueue`.
    private func attemptConnect(_ peripheral: CBPeripheral) {
        targetPeripheral = peripheral
        setState(.connecting)
        centralManager.connect(peripheral, options: nil)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectTimeoutTimer?.invalidate()
            self.connectTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
                self?.bleQueue.async { self?.handleConnectTimeout() }
            }
        }
    }

    private func invalidateConnectTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.connectTimeoutTimer?.invalidate()
            self?.connectTimeoutTimer = nil
        }
    }

    /// Must run on `bleQueue`.
    private func handleConnectTimeout() {
        guard let peripheral = targetPeripheral else { return }
        BLELog.shared.log("connect timed out after 8s (alreadyRetried=\(hasRetriedConnect))")
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
        bleQueue.async { [weak self] in
            guard let self = self else { return }
            BLELog.shared.log("disconnect() requested")
            if let peripheral = self.targetPeripheral {
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
            self.targetPeripheral = nil
            self.writeCharacteristic = nil
            self.notifyCharacteristic = nil
            self.setState(.disconnected)
        }
    }

    func send(_ data: Data) {
        bleQueue.async { [weak self] in
            guard let self = self,
                  let peripheral = self.targetPeripheral,
                  let characteristic = self.writeCharacteristic else { return }
            peripheral.writeValue(data, for: characteristic, type: self.writeType)
        }
    }
}

extension BLETransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        BLELog.shared.log("centralManagerDidUpdateState -> \(BLETransport.describe(central.state))")

        if central.state == .poweredOn {
            // Covers both the cold-start race (a scan was requested before
            // the central settled) and Bluetooth being toggled back on
            // mid-session.
            if scanPending {
                startScanIfPowered(trigger: "deferred scan after poweredOn")
            }
            return
        }

        if transportState == .scanning {
            setState(.error("Bluetooth turned off while scanning"))
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier.uuidString
        let isNew = discoveredPeripherals[id] == nil
        discoveredPeripherals[id] = peripheral

        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? localName ?? "Unknown device"

        if isNew {
            // Advertised service UUIDs are logged because they settle the
            // "is my configured service UUID right?" question before a
            // connection is ever attempted.
            let advertisedServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
                .map { $0.uuidString }.joined(separator: ",") ?? "none"
            BLELog.shared.log("didDiscover #\(discoveredPeripherals.count): name=\(name) rssi=\(RSSI) services=[\(advertisedServices)] id=\(id)")
        }

        let device = DiscoveredPeripheral(id: id, name: name, signalStrength: RSSI.intValue)
        let callback = onDiscovered
        DispatchQueue.main.async {
            callback?(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        invalidateConnectTimer()
        BLELog.shared.log("didConnect \(peripheral.name ?? "unnamed") — discovering services")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        invalidateConnectTimer()
        BLELog.shared.log("didFailToConnect: \(error?.localizedDescription ?? "unknown error")")
        setState(.error("Failed to connect: \(error?.localizedDescription ?? "unknown error")"))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        writeCharacteristic = nil
        notifyCharacteristic = nil
        BLELog.shared.log("didDisconnectPeripheral: \(error?.localizedDescription ?? "clean disconnect")")
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
            BLELog.shared.log("didDiscoverServices: none (error=\(error?.localizedDescription ?? "nil"))")
            setState(.error("No services found on adapter"))
            return
        }
        BLELog.shared.log("didDiscoverServices: [\(services.map { $0.uuid.uuidString }.joined(separator: ","))]")
        guard let targetService = services.first(where: { $0.uuid == config.serviceUUID }) else {
            setState(.error("Configured service UUID \(config.serviceUUID) not found on this device — check Settings against your adapter's real UUID"))
            return
        }
        peripheral.discoverCharacteristics(nil, for: targetService)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else {
            BLELog.shared.log("didDiscoverCharacteristicsFor \(service.uuid): none (error=\(error?.localizedDescription ?? "nil"))")
            setState(.error("No characteristics found for configured service"))
            return
        }
        BLELog.shared.log("didDiscoverCharacteristicsFor \(service.uuid): [\(characteristics.map { $0.uuid.uuidString }.joined(separator: ","))]")

        writeCharacteristic = characteristics.first(where: { $0.uuid == config.writeCharacteristicUUID })
        notifyCharacteristic = characteristics.first(where: { $0.uuid == config.notifyCharacteristicUUID })

        guard let notifyCharacteristic = notifyCharacteristic else {
            setState(.error("Configured notify characteristic UUID not found — check Settings"))
            return
        }
        guard let writeCharacteristic = writeCharacteristic else {
            setState(.error("Configured write characteristic UUID not found — check Settings"))
            return
        }
        guard let resolvedWriteType = BLETransport.resolveWriteType(preferred: config.writeType, properties: writeCharacteristic.properties) else {
            setState(.error("Configured write characteristic \(writeCharacteristic.uuid) is not writable — check Settings"))
            return
        }
        writeType = resolvedWriteType
        BLELog.shared.log("write=\(writeCharacteristic.uuid) properties=\(writeCharacteristic.properties.rawValue) using \(resolvedWriteType == .withResponse ? "withResponse" : "withoutResponse"); notify=\(notifyCharacteristic.uuid) properties=\(notifyCharacteristic.properties.rawValue)")

        // `.connected` starts the ELM327 init, so it waits for the adapter to
        // confirm notifications are on — a reply sent before that would be lost.
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    /// Honours the configured write type when the adapter supports it. A write
    /// of a type the characteristic does not offer may never reach the adapter.
    static func resolveWriteType(preferred: CBCharacteristicWriteType,
                                 properties: CBCharacteristicProperties) -> CBCharacteristicWriteType? {
        let canWrite = properties.contains(.write)
        let canWriteWithoutResponse = properties.contains(.writeWithoutResponse)
        switch preferred {
        case .withResponse where canWrite: return .withResponse
        case .withoutResponse where canWriteWithoutResponse: return .withoutResponse
        default:
            if canWrite { return .withResponse }
            return canWriteWithoutResponse ? .withoutResponse : nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == config.notifyCharacteristicUUID else { return }
        if let error = error {
            setState(.error("Could not enable notifications on \(characteristic.uuid): \(error.localizedDescription)"))
            return
        }
        BLELog.shared.log("notifications on \(characteristic.uuid): isNotifying=\(characteristic.isNotifying)")
        guard characteristic.isNotifying else {
            setState(.error("Adapter did not enable notifications on \(characteristic.uuid)"))
            return
        }
        setState(.connected)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == config.notifyCharacteristicUUID, let data = characteristic.value else { return }
        onDataReceived?(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            BLELog.shared.log("didWriteValueFor \(characteristic.uuid) failed: \(error.localizedDescription)")
            setState(.error("Write failed: \(error.localizedDescription)"))
        }
    }
}
