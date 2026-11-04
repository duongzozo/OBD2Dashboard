import Foundation

/// Single app-wide source of vehicle telemetry. Owns the `OBDEngine` so
/// Dashboard, Live Data, Fuel Economy, and Trip Computer all observe the exact
/// same stream instead of each polling on its own (which would duplicate
/// requests and let trip totals disagree between tabs). Started once from
/// `RootTabBarController` and runs for the app's lifetime, matching the Trip
/// Computer's need to keep accumulating regardless of which tab is on screen.
final class TelemetryHub {
    static let shared = TelemetryHub()

    let snapshot: Observable<TelemetrySnapshot> = Observable(.empty)
    let bluetoothState: Observable<ConnectionState> = Observable(.disconnected)
    let ecuState: Observable<ConnectionState> = Observable(.disconnected)
    let supportedPIDs: Observable<Set<OBDPID>> = Observable([])
    let vehicleInfo: Observable<VehicleInfo> = Observable(.unknown)
    let tripComputer = TripComputer()

    private let bluetoothManager: BluetoothManager
    private let settingsStore: SettingsStore
    private var engine: OBDEngine?

    init(settingsStore: SettingsStore = .shared, bluetoothManager: BluetoothManager = .shared) {
        self.settingsStore = settingsStore
        self.bluetoothManager = bluetoothManager
    }

    func start() {
        guard engine == nil else { return }

        let realEngine = OBDEngine(bluetoothManager: bluetoothManager)
        engine = realEngine
        bluetoothManager.connectionState.observe { [weak self] state in
            self?.bluetoothState.value = state
        }
        realEngine.ecuState.observe { [weak self] state in
            self?.ecuState.value = state
        }
        realEngine.supportedPIDs.observe { [weak self] pids in
            self?.supportedPIDs.value = pids
        }
        realEngine.vehicleInfo.observe { [weak self] info in
            self?.vehicleInfo.value = info
        }
        realEngine.onSnapshotUpdate = { [weak self] snapshot in
            self?.handle(snapshot)
        }
        bluetoothManager.autoReconnectIfEnabled()
    }

    private func handle(_ newSnapshot: TelemetrySnapshot) {
        snapshot.value = newSnapshot
        let profile = settingsStore.settings.value.vehicleProfile
        let fuelRate = FuelConsumptionEngine.fuelRate(snapshot: newSnapshot, profile: profile)
        tripComputer.update(with: newSnapshot, fuelRateLitersPerHour: fuelRate?.litersPerHour)
    }
}
