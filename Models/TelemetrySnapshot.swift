import Foundation

/// A single timestamped reading of one vehicle parameter, tagged with where
/// the value came from. Both the real OBD engine (later phases) and the
/// Phase 1 simulator produce these, so the dashboard/view models never need
/// to know which source they're looking at.
struct TelemetryValue: Equatable {
    var value: Double
    var source: DataSource
    var timestamp: Date

    static func simulated(_ value: Double, at timestamp: Date = Date()) -> TelemetryValue {
        TelemetryValue(value: value, source: .simulated, timestamp: timestamp)
    }
}

/// A full set of vehicle parameters at one point in time. Fields are optional
/// because real ECUs only report PIDs they actually support — nothing here
/// may be assumed present.
struct TelemetrySnapshot: Equatable {
    var timestamp: Date = Date()

    var vehicleSpeedKmh: TelemetryValue?
    var engineRpm: TelemetryValue?
    var coolantTempCelsius: TelemetryValue?
    var controlModuleVoltage: TelemetryValue?
    var engineLoadPercent: TelemetryValue?
    var throttlePositionPercent: TelemetryValue?
    var intakeAirTempCelsius: TelemetryValue?
    var mafGramsPerSec: TelemetryValue?
    var fuelTankLevelPercent: TelemetryValue?
    var engineFuelRateLitersPerHour: TelemetryValue?
    var ambientAirTempCelsius: TelemetryValue?
    var engineRuntimeSeconds: TelemetryValue?
    var shortTermFuelTrimPercent: TelemetryValue?
    var longTermFuelTrimPercent: TelemetryValue?
    var timingAdvanceDegrees: TelemetryValue?

    static let empty = TelemetrySnapshot()
}
