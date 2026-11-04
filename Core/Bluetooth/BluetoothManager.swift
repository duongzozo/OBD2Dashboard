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

    /// The remembered adapter being looked for. Connecting as soon as it shows
    /// up copes with an adapter that only powers on after the app has started.
    private var autoConnectTargetID: String?
    private var autoConnectTimeout: DispatchWorkItem?
    private var linkIsUp = false
    private var userRequestedDisconnect = false

    private static let autoConnectSearchSeconds = 60.0
    private static let reconnectDelaySeconds = 2.0

    init(settingsStore: SettingsStore = .shared) {
        self.settingsStore = settingsStore
        self.transport = BLETransport(config: BLEAdapterConfig(settings: settingsStore.settings.value))

        transport.state.observe { [weak self] state in
            self?.connectionState.value = state
            self?.handleLinkState(state)
        }
    }

    func scan() {
        guard connectionState.value != .connected, connectionState.value != .ecuReady else {
            BLELog.shared.log("scan() ignored — already \(connectionState.value.shortLabel)")
            return
        }
        cancelAutoConnect()
        BLELog.shared.log("scan() requested")
        startScanning()
    }

    func stopScan() {
        cancelAutoConnect()
        transport.stopScan()
    }

    func connect(to peripheralID: String) {
        cancelAutoConnect()
        transport.connect(to: peripheralID)
        UserDefaults.standard.set(peripheralID, forKey: lastConnectedKey)
    }

    func disconnect() {
        cancelAutoConnect()
        userRequestedDisconnect = true
        transport.disconnect()
    }

    /// Called at app start, and again when an established link drops — looks
    /// for the last-used adapter without requiring a manual scan, if enabled
    /// in Settings.
    func autoReconnectIfEnabled() {
        guard settingsStore.settings.value.autoReconnectEnabled,
              let lastID = UserDefaults.standard.string(forKey: lastConnectedKey) else {
            BLELog.shared.log("autoReconnect skipped — disabled or no previous peripheral stored")
            return
        }
        BLELog.shared.log("autoReconnect: looking for previously used peripheral \(lastID)")
        cancelAutoConnect()
        autoConnectTargetID = lastID

        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, self.autoConnectTargetID != nil else { return }
            BLELog.shared.log("autoReconnect: adapter not found, giving up")
            self.stopScan()
        }
        autoConnectTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoConnectSearchSeconds, execute: timeout)

        startScanning()
    }

    private func startScanning() {
        discoveredDevices.value = []
        transport.startScan { [weak self] device in
            self?.recordDiscovered(device)
        }
    }

    private func recordDiscovered(_ device: DiscoveredPeripheral) {
        var current = discoveredDevices.value
        if let index = current.firstIndex(where: { $0.id == device.id }) {
            current[index] = device
        } else {
            current.append(device)
        }
        discoveredDevices.value = current

        if device.id == autoConnectTargetID {
            BLELog.shared.log("autoReconnect: found \(device.name), connecting")
            connect(to: device.id)
        }
    }

    private func cancelAutoConnect() {
        autoConnectTargetID = nil
        autoConnectTimeout?.cancel()
        autoConnectTimeout = nil
    }

    /// Reconnects after an unexpected loss of an established link, such as the
    /// ignition cutting power to the adapter. A failed first connection does
    /// not retry here: the user asked for it and should see the error.
    private func handleLinkState(_ state: ConnectionState) {
        switch state {
        case .connected:
            linkIsUp = true
            userRequestedDisconnect = false
        case .disconnected, .error:
            let wasUnexpected = linkIsUp && !userRequestedDisconnect
            linkIsUp = false
            userRequestedDisconnect = false
            guard wasUnexpected else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.reconnectDelaySeconds) { [weak self] in
                // The user may have started something else in the meantime.
                guard let self = self, !self.linkIsUp else { return }
                switch self.connectionState.value {
                case .disconnected, .error: self.autoReconnectIfEnabled()
                default: break
                }
            }
        default:
            break
        }
    }
}
