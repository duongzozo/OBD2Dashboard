import Foundation

/// Accumulated distance/fuel/time for a trip. `averagePer100km` is `nil`
/// until enough distance has accumulated to be meaningful — never divides
/// by a near-zero distance.
struct TripRecord: Codable, Equatable {
    var distanceKm: Double = 0
    var fuelUsedLiters: Double = 0
    var elapsedSeconds: Double = 0
    var startedAt: Date = Date()

    var averageConsumptionPer100km: Double? {
        guard distanceKm > 0.05 else { return nil }
        return fuelUsedLiters * 100.0 / distanceKm
    }
}

/// Tracks both a "current trip" (resettable any time, e.g. each drive) and
/// a "since-reset" total (persists until the user explicitly resets it,
/// e.g. since last fill-up) — spec §6: "Current trip average... Since
/// reset average... Reset trip." Fed by `TelemetryHub` on every snapshot;
/// not a standalone poller.
final class TripComputer {
    let currentTrip: Observable<TripRecord> = Observable(TripRecord())
    let sinceReset: Observable<TripRecord> = Observable(TripRecord())

    private let defaults: UserDefaults
    private let sinceResetKey = "com.diy.obd2dashboard.tripComputer.sinceReset"
    private var lastTimestamp: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: sinceResetKey),
           let decoded = try? JSONDecoder().decode(TripRecord.self, from: data) {
            sinceReset.value = decoded
        }
    }

    /// `fuelRateLitersPerHour` should come from `FuelConsumptionEngine`'s
    /// ECU/MAF-sourced rate — never a placeholder, per spec §6 ("Không
    /// dùng giá trị mẫu hoặc dữ liệu giả làm kết quả thực tế").
    func update(with newSnapshot: TelemetrySnapshot, fuelRateLitersPerHour: Double?) {
        let now = newSnapshot.timestamp
        defer { lastTimestamp = now }
        guard let last = lastTimestamp else { return }
        let dt = now.timeIntervalSince(last)
        guard dt > 0, dt < 5 else { return } // Guards against clock jumps / timeout gaps.
        guard let speed = newSnapshot.vehicleSpeedKmh?.value else { return }

        let distanceDelta = speed * (dt / 3600.0)
        let fuelDelta = (fuelRateLitersPerHour ?? 0) * (dt / 3600.0)
        let timeDelta = speed > 0.5 ? dt : 0

        var current = currentTrip.value
        current.distanceKm += distanceDelta
        current.fuelUsedLiters += fuelDelta
        current.elapsedSeconds += timeDelta
        currentTrip.value = current

        var reset = sinceReset.value
        reset.distanceKm += distanceDelta
        reset.fuelUsedLiters += fuelDelta
        reset.elapsedSeconds += timeDelta
        sinceReset.value = reset
        persistSinceReset()
    }

    func resetCurrentTrip() {
        currentTrip.value = TripRecord()
    }

    func resetSinceReset() {
        sinceReset.value = TripRecord()
        persistSinceReset()
    }

    private func persistSinceReset() {
        guard let data = try? JSONEncoder().encode(sinceReset.value) else { return }
        defaults.set(data, forKey: sinceResetKey)
    }
}
