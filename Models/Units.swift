import Foundation

enum SpeedUnit: String, Codable, CaseIterable, Equatable {
    case kmh, mph

    func convert(fromKmh kmh: Double) -> Double {
        switch self {
        case .kmh: return kmh
        case .mph: return kmh * 0.621371
        }
    }

    var symbol: String {
        switch self {
        case .kmh: return "km/h"
        case .mph: return "mph"
        }
    }
}

enum TemperatureUnit: String, Codable, CaseIterable, Equatable {
    case celsius, fahrenheit

    func convert(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius: return celsius
        case .fahrenheit: return celsius * 9.0 / 5.0 + 32.0
        }
    }

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }
}

/// Distinguishes where a telemetry value came from so the UI can disclose
/// confidence instead of presenting everything as equally authoritative.
enum DataSource: String, Codable, Equatable {
    case ecuReported      // Directly reported by a Mode 01 PID (e.g. PID 5E fuel rate)
    case calculated        // Derived from other ECU PIDs via a documented formula (e.g. MAF-based fuel rate)
    case estimated          // Rough estimate when neither of the above is available
    case simulated          // Phase 1 DEMO MODE synthetic data

    var displayLabel: String {
        switch self {
        case .ecuReported: return "ECU"
        case .calculated: return "CALC"
        case .estimated: return "EST"
        case .simulated: return "DEMO"
        }
    }
}
