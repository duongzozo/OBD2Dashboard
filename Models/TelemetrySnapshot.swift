import Foundation

/// A single timestamped reading of one vehicle parameter, tagged with where
/// the value came from.
struct TelemetryValue: Equatable {
    var value: Double
    var source: DataSource
    var timestamp: Date

    static func ecuReported(_ value: Double, at timestamp: Date = Date()) -> TelemetryValue {
        TelemetryValue(value: value, source: .ecuReported, timestamp: timestamp)
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
    var oxygenSensor1VoltageVolts: TelemetryValue?

    static let empty = TelemetrySnapshot()

    func value(for pid: OBDPID) -> TelemetryValue? {
        switch pid {
        case .vehicleSpeed: return vehicleSpeedKmh
        case .engineRPM: return engineRpm
        case .coolantTemp: return coolantTempCelsius
        case .controlModuleVoltage: return controlModuleVoltage
        case .engineLoad: return engineLoadPercent
        case .throttlePosition: return throttlePositionPercent
        case .intakeAirTemp: return intakeAirTempCelsius
        case .mafAirFlow: return mafGramsPerSec
        case .fuelTankLevel: return fuelTankLevelPercent
        case .engineFuelRate: return engineFuelRateLitersPerHour
        case .ambientAirTemp: return ambientAirTempCelsius
        case .engineRuntime: return engineRuntimeSeconds
        case .shortFuelTrim1: return shortTermFuelTrimPercent
        case .longFuelTrim1: return longTermFuelTrimPercent
        case .timingAdvance: return timingAdvanceDegrees
        case .oxygenSensor1: return oxygenSensor1VoltageVolts
        case .monitorStatus: return nil
        }
    }
}
