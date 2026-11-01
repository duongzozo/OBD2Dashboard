import Foundation

/// All user-configurable preferences, persisted as a single JSON blob.
/// Phase 1 only exercises a subset (vehicle profile, units, warnings, demo
/// toggle); later phases add adapter/BLE UUID fields without needing to
/// migrate existing stored data, since all fields are decoded with defaults.
struct AppSettings: Codable, Equatable {
    var vehicleProfile: VehicleProfile = .fordEscape2009XLT
    var speedUnit: SpeedUnit = .kmh
    var temperatureUnit: TemperatureUnit = .celsius
    var dashboardPollingIntervalMs: Int = 150
    var coolantWarningCelsius: Double = 110
    var voltageWarningLow: Double = 11.8
    var voltageWarningHigh: Double = 15.0
    var speedWarningKmh: Double = 140
    var nightModeEnabled: Bool = false
    var powerSaveModeEnabled: Bool = false
    var demoModeEnabled: Bool = true

    static let `default` = AppSettings()
}
