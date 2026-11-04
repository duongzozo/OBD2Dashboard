import Foundation

/// Drives the Dashboard screen. All telemetry comes from the shared
/// `TelemetryHub` (one engine for the whole app, started once at
/// launch) — this view model just re-exposes its observables plus clock
/// and vehicle-name bindings the view controller needs.
final class DashboardViewModel {
    let snapshot: Observable<TelemetrySnapshot>
    let bluetoothState: Observable<ConnectionState>
    let ecuState: Observable<ConnectionState>
    let vehicleName: Observable<String>
    let clockText: Observable<String> = Observable("")
    let tripComputer: TripComputer

    private var clockTimer: Timer?

    init(settingsStore: SettingsStore = .shared, hub: TelemetryHub = .shared) {
        self.snapshot = hub.snapshot
        self.bluetoothState = hub.bluetoothState
        self.ecuState = hub.ecuState
        self.tripComputer = hub.tripComputer
        self.vehicleName = Observable(settingsStore.settings.value.vehicleProfile.name)

        settingsStore.settings.observe { [weak self] settings in
            self?.vehicleName.value = settings.vehicleProfile.name
        }
    }

    deinit {
        clockTimer?.invalidate()
    }

    func start() {
        startClock()
    }

    func stop() {
        clockTimer?.invalidate()
        clockTimer = nil
    }

    private func startClock() {
        clockTimer?.invalidate()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.clockText.value = formatter.string(from: Date())
        }
        clockText.value = formatter.string(from: Date())
    }
}
