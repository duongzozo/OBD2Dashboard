import Foundation

/// A single fuel-consumption reading, explicit about units and source so
/// the UI never presents ECU/calculated/estimated values as equally
/// authoritative (spec §6: "Phải phân biệt... Hiển thị nguồn dữ liệu và
/// độ tin cậy").
struct FuelConsumptionResult: Equatable {
    var value: Double
    var isPer100km: Bool // false => L/h (near-zero speed), true => L/100km
    var source: DataSource
}

/// Pure calculation, no I/O — takes one telemetry snapshot + the active
/// `VehicleProfile` and returns a fuel-consumption reading, or `nil` when
/// there's genuinely nothing to compute from (never fabricates a value).
struct FuelConsumptionEngine {
    static func compute(snapshot: TelemetrySnapshot, profile: VehicleProfile) -> FuelConsumptionResult? {
        let fuelRateLph: Double
        let source: DataSource

        if let ecuRate = snapshot.engineFuelRateLitersPerHour, ecuRate.source == .ecuReported {
            // PID 5E reported directly by the ECU — highest-confidence source.
            fuelRateLph = ecuRate.value
            source = .ecuReported
        } else if let maf = snapshot.mafGramsPerSec?.value, maf > 0, profile.airFuelRatio > 0, profile.fuelDensityGramsPerLiter > 0 {
            // Fuel rate (L/h) = MAF (g/s) * 3600 / (AFR * density) — spec §6.
            fuelRateLph = maf * 3600.0 / (profile.airFuelRatio * profile.fuelDensityGramsPerLiter)
            source = .calculated
        } else if let simulated = snapshot.engineFuelRateLitersPerHour, simulated.source == .simulated {
            // DEMO MODE passthrough — still clearly tagged, never presented as real.
            fuelRateLph = simulated.value
            source = .simulated
        } else {
            return nil
        }

        guard fuelRateLph.isFinite, fuelRateLph >= 0 else { return nil }

        guard let speed = snapshot.vehicleSpeedKmh?.value, speed >= 3 else {
            // Engine off/idle/crawling — L/h is the only meaningful unit
            // (spec §6: never divide by a near-zero speed).
            return FuelConsumptionResult(value: fuelRateLph, isPer100km: false, source: source)
        }

        let per100km = fuelRateLph * 100.0 / speed
        return FuelConsumptionResult(value: per100km, isPer100km: true, source: source)
    }
}
