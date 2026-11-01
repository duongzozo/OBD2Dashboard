import Foundation

/// Drives the Dashboard screen. Picks its data source based on
/// `AppSettings.demoModeEnabled`: the `OBDSimulator` (DEMO MODE) or a real
/// `OBDEngine` talking to the adapter via `BluetoothManager`. Either way
/// the view controller binds to the same `snapshot`/`bluetoothState`/
/// `ecuState` observables — it never knows which source is live.
final class DashboardViewModel {
    let snapshot: Observable<TelemetrySnapshot> = Observable(.empty)
    let bluetoothState: Observable<ConnectionState> = Observable(.demoMode)
    let ecuState: Observable<ConnectionState> = Observable(.demoMode)
    let vehicleName: Observable<String>
    let clockText: Observable<String> = Observable("")

    // Minimal trip accumulation so the footer has something to show while
    // the full Fuel Consumption Engine / Trip Computer (Phase 4) isn't
    // wired in here yet — kept intentionally simple.
    let tripDistanceKm: Observable<Double> = Observable(0)
    let tripElapsedSeconds: Observable<Double> = Observable(0)
    let tripFuelUsedLiters: Observable<Double> = Observable(0)

    private let simulator: OBDSimulator
    private let bluetoothManager: BluetoothManager
    private let settingsStore: SettingsStore
    private var engine: OBDEngine?
    private var clockTimer: Timer?
    private var lastTickDate: Date?

    init(settingsStore: SettingsStore = .shared, bluetoothManager: BluetoothManager = .shared) {
        self.settingsStore = settingsStore
        self.bluetoothManager = bluetoothManager
        self.vehicleName = Observable(settingsStore.settings.value.vehicleProfile.name)
        let interval = settingsStore.settings.value.dashboardPollingIntervalMs
        self.simulator = OBDSimulator(config: .init(fastIntervalMs: interval, slowIntervalMs: 1000))

        settingsStore.settings.observe { [weak self] settings in
            self?.vehicleName.value = settings.vehicleProfile.name
        }
    }

    func start() {
        startClock()
        if settingsStore.settings.value.demoModeEnabled {
            startDemoMode()
        } else {
            startRealEngine()
        }
    }

    func stop() {
        simulator.stop()
        engine?.stop()
        clockTimer?.invalidate()
        clockTimer = nil
    }

    private func startDemoMode() {
        bluetoothState.value = .demoMode
        ecuState.value = .demoMode
        simulator.onSnapshotUpdate = { [weak self] snapshot in
            self?.handle(snapshot)
        }
        simulator.start()
    }

    private func startRealEngine() {
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

    private func handle(_ newSnapshot: TelemetrySnapshot) {
        snapshot.value = newSnapshot
        accumulateTrip(with: newSnapshot)
    }

    private func accumulateTrip(with newSnapshot: TelemetrySnapshot) {
        let now = newSnapshot.timestamp
        defer { lastTickDate = now }
        guard let last = lastTickDate else { return }
        let dt = now.timeIntervalSince(last)
        guard dt > 0, dt < 5 else { return }

        if let speed = newSnapshot.vehicleSpeedKmh?.value {
            tripDistanceKm.value += speed * (dt / 3600.0)
            if speed > 0.5 {
                tripElapsedSeconds.value += dt
            }
        }
        if let fuelRate = newSnapshot.engineFuelRateLitersPerHour?.value {
            tripFuelUsedLiters.value += fuelRate * (dt / 3600.0)
        }
    }

    private func startClock() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.clockText.value = formatter.string(from: Date())
        }
        clockText.value = formatter.string(from: Date())
    }
}
