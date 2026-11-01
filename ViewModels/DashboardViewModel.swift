import Foundation

/// Drives the Dashboard screen. In Phase 1 the data source is always the
/// `OBDSimulator`; later phases swap in a real `OBDEngine` behind the same
/// `onSnapshotUpdate`-style interface without the view controller noticing.
final class DashboardViewModel {
    let snapshot: Observable<TelemetrySnapshot> = Observable(.empty)
    let connectionState: Observable<ConnectionState> = Observable(.demoMode)
    let vehicleName: Observable<String>
    let clockText: Observable<String> = Observable("")

    // Minimal trip accumulation so the footer has something real to show
    // in Phase 1. This is simulator-driven bookkeeping, not the full Fuel
    // Consumption Engine (Phase 4) — kept intentionally simple.
    let tripDistanceKm: Observable<Double> = Observable(0)
    let tripElapsedSeconds: Observable<Double> = Observable(0)
    let tripFuelUsedLiters: Observable<Double> = Observable(0)

    private let simulator: OBDSimulator
    private var clockTimer: Timer?
    private var lastTickDate: Date?

    init(settingsStore: SettingsStore = .shared) {
        self.vehicleName = Observable(settingsStore.settings.value.vehicleProfile.name)
        let interval = settingsStore.settings.value.dashboardPollingIntervalMs
        self.simulator = OBDSimulator(config: .init(fastIntervalMs: interval, slowIntervalMs: 1000))

        settingsStore.settings.observe { [weak self] settings in
            self?.vehicleName.value = settings.vehicleProfile.name
        }
    }

    func start() {
        simulator.onSnapshotUpdate = { [weak self] snapshot in
            self?.handle(snapshot)
        }
        simulator.start()
        startClock()
    }

    func stop() {
        simulator.stop()
        clockTimer?.invalidate()
        clockTimer = nil
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
