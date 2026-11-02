import Foundation

/// Owns the `BluetoothTransport` and exposes scan/connect lifecycle to the
/// UI. Deliberately stops at `.connected` — it has no knowledge of OBD-II
/// at all (one-directional dependency: `Core/OBD` depends on
/// `Core/Bluetooth`, never the reverse). Once connected, `OBDEngine` takes
/// the same `transport` reference, runs the ELM327 init sequence over it,
/// and reports `.initializing`/`.ecuReady` through its own, separate
/// state — matching the dashboard header's two independent status pills
/// (Bluetooth status vs ECU status, spec §4.A).
final class BluetoothManager {
    static let shared = BluetoothManager()

    let connectionState: Observable<ConnectionState> = Observable(.disconnected)
    let discoveredDevices: Observable<[DiscoveredPeripheral]> = Observable([])
    let transport: BluetoothTransport

    private let settingsStore: SettingsStore
    private let lastConnectedKey = "com.diy.obd2dashboard.lastConnectedPeripheralID"

    init(settingsStore: SettingsStore = .shared) {
        self.settingsStore = settingsStore
        self.transport = BLETransport(config: BLEAdapterConfig(settings: settingsStore.settings.value))

        transport.state.observe { [weak self] state in
            self?.connectionState.value = state
        }
    }

    func scan() {
        guard connectionState.value != .connected, connectionState.value != .ecuReady else {
            BLELog.shared.log("scan() ignored — already \(connectionState.value.shortLabel)")
            return
        }
        BLELog.shared.log("scan() requested")
        discoveredDevices.value = []
        transport.startScan { [weak self] device in
            guard let self = self else { return }
            var current = self.discoveredDevices.value
            if let index = current.firstIndex(where: { $0.id == device.id }) {
                current[index] = device
            } else {
                current.append(device)
            }
            self.discoveredDevices.value = current
        }
    }

    func stopScan() {
        transport.stopScan()
    }

    func connect(to peripheralID: String) {
        transport.connect(to: peripheralID)
        UserDefaults.standard.set(peripheralID, forKey: lastConnectedKey)
    }

    func disconnect() {
        transport.disconnect()
    }

    /// Called at app start — reconnects to the last-used adapter without
    /// requiring the user to scan again every time, if enabled in Settings.
    func autoReconnectIfEnabled() {
        guard settingsStore.settings.value.autoReconnectEnabled,
              let lastID = UserDefaults.standard.string(forKey: lastConnectedKey) else {
            BLELog.shared.log("autoReconnect skipped — disabled or no previous peripheral stored")
            return
        }
        BLELog.shared.log("autoReconnect: scanning for previously used peripheral \(lastID)")
        scan()
        // Give the scan a moment to re-discover the previously paired
        // device by ID before attempting to connect to it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            BLELog.shared.log("autoReconnect: attempting connect to \(lastID)")
            self?.connect(to: lastID)
        }
    }
}
