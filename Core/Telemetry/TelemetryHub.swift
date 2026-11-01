import Foundation

/// Single app-wide source of vehicle telemetry. Owns whichever data source
/// is active — `OBDSimulator` in DEMO MODE, or the real `OBDEngine` once
/// connected — so Dashboard, Live Data, Fuel Economy, and Trip Computer
/// all observe the exact same stream instead of each starting its own
/// simulator/engine (which would duplicate polling and let trip totals
/// disagree between tabs). Started once from `RootTabBarController` and
/// runs for the app's lifetime, matching the Trip Computer's need to keep
/// accumulating regardless of which tab is on screen.
final class TelemetryHub {
    static let shared = TelemetryHub()

    let snapshot: Observable<TelemetrySnapshot> = Observable(.empty)
    let bluetoothState: Observable<ConnectionState> = Observable(.demoMode)
    let ecuState: Observable<ConnectionState> = Observable(.demoMode)
    let tripComputer = TripComputer()

    private let simulator: OBDSimulator
    private let bluetoothManager: BluetoothManager
    private let settingsStore: SettingsStore
    private var engine: OBDEngine?
    private var isRunning = false

    init(settingsStore: SettingsStore = .shared, bluetoothManager: BluetoothManager = .shared) {
        self.settingsStore = settingsStore
        self.bluetoothManager = bluetoothManager
        let interval = settingsStore.settings.value.dashboardPollingIntervalMs
        self.simulator = OBDSimulator(config: .init(fastIntervalMs: interval, slowIntervalMs: 1000))
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        if settingsStore.settings.value.demoModeEnabled {
            bluetoothState.value = .demoMode
            ecuState.value = .demoMode
            simulator.onSnapshotUpdate = { [weak self] snapshot in
                self?.handle(snapshot)
            }
            simulator.start()
        } else {
            let realEngine = OBDEngine(bluetoothManager: bluetoothManager)
            engine = realEngine
            bluetoothManager.connectionState.observe { [weak self] state in
                self?.bluetoothState.value = state
            }
            realEngine.ecuState.observe { [weak self] state in
                self?.ecuState.value = state
            }
            realEngine.onSnapshotUpdate = { [weak self] snapshot in
                self?.handle(snapshot)
            }
            bluetoothManager.autoReconnectIfEnabled()
        }
    }

    private func handle(_ newSnapshot: TelemetrySnapshot) {
        snapshot.value = newSnapshot
        tripComputer.update(with: newSnapshot, fuelRateLitersPerHour: newSnapshot.engineFuelRateLitersPerHour?.value)
    }
}
