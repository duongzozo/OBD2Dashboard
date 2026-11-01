import Foundation

/// How the BLE transport writes commands to the adapter's write
/// characteristic. Most notify-based ELM327 clones (CC2541/HM-10 style)
/// expect `.withoutResponse`; some expect `.withResponse` — configurable
/// per-adapter since the spec forbids assuming this.
enum BLEWriteType: String, Codable, Equatable, CaseIterable {
    case withoutResponse
    case withResponse
}

/// All user-configurable preferences, persisted as a single JSON blob.
///
/// Uses a hand-written `Decodable` implementation (instead of relying on
/// synthesis) so that adding a new field in a later phase does NOT throw
/// away a user's previously-saved settings: synthesized `Decodable` treats
/// a missing key as a hard decode error regardless of the property's
/// default value, which would make `SettingsStore` silently fall back to
/// `.default` and discard everything the user configured. `decodeIfPresent`
/// here preserves true backward compatibility across phases.
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

    // Phase 2 — Bluetooth adapter configuration. Defaults match the most
    // common BLE-ELM327-clone UUID set (HM-10/CC2541-style SPP bridge:
    // service FFF0, notify FFF1, write FFF2) but MUST be overridable here
    // without a code change once the real adapter's UUIDs are confirmed.
    var bleServiceUUID: String = "FFF0"
    var bleWriteCharacteristicUUID: String = "FFF2"
    var bleNotifyCharacteristicUUID: String = "FFF1"
    var bleWriteType: BLEWriteType = .withoutResponse
    var obdRequestTimeoutMs: Int = 2000
    var autoReconnectEnabled: Bool = true

    static let `default` = AppSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.default
        vehicleProfile = try container.decodeIfPresent(VehicleProfile.self, forKey: .vehicleProfile) ?? defaults.vehicleProfile
        speedUnit = try container.decodeIfPresent(SpeedUnit.self, forKey: .speedUnit) ?? defaults.speedUnit
        temperatureUnit = try container.decodeIfPresent(TemperatureUnit.self, forKey: .temperatureUnit) ?? defaults.temperatureUnit
        dashboardPollingIntervalMs = try container.decodeIfPresent(Int.self, forKey: .dashboardPollingIntervalMs) ?? defaults.dashboardPollingIntervalMs
        coolantWarningCelsius = try container.decodeIfPresent(Double.self, forKey: .coolantWarningCelsius) ?? defaults.coolantWarningCelsius
        voltageWarningLow = try container.decodeIfPresent(Double.self, forKey: .voltageWarningLow) ?? defaults.voltageWarningLow
        voltageWarningHigh = try container.decodeIfPresent(Double.self, forKey: .voltageWarningHigh) ?? defaults.voltageWarningHigh
        speedWarningKmh = try container.decodeIfPresent(Double.self, forKey: .speedWarningKmh) ?? defaults.speedWarningKmh
        nightModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .nightModeEnabled) ?? defaults.nightModeEnabled
        powerSaveModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .powerSaveModeEnabled) ?? defaults.powerSaveModeEnabled
        demoModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .demoModeEnabled) ?? defaults.demoModeEnabled
        bleServiceUUID = try container.decodeIfPresent(String.self, forKey: .bleServiceUUID) ?? defaults.bleServiceUUID
        bleWriteCharacteristicUUID = try container.decodeIfPresent(String.self, forKey: .bleWriteCharacteristicUUID) ?? defaults.bleWriteCharacteristicUUID
        bleNotifyCharacteristicUUID = try container.decodeIfPresent(String.self, forKey: .bleNotifyCharacteristicUUID) ?? defaults.bleNotifyCharacteristicUUID
        bleWriteType = try container.decodeIfPresent(BLEWriteType.self, forKey: .bleWriteType) ?? defaults.bleWriteType
        obdRequestTimeoutMs = try container.decodeIfPresent(Int.self, forKey: .obdRequestTimeoutMs) ?? defaults.obdRequestTimeoutMs
        autoReconnectEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoReconnectEnabled) ?? defaults.autoReconnectEnabled
    }
}
