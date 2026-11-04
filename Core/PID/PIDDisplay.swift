import Foundation

/// How a PID is presented to the driver: the unit it is shown in and how many
/// decimals are useful. Values are stored in metric and converted only here.
enum PIDDisplay {
    /// Everything the Live Data screen and CSV log cover. Monitor status is a
    /// bit field rather than a measurement, so it has no row.
    static let measuredPIDs: [OBDPID] = OBDPID.allCases.filter { $0 != .monitorStatus }

    static func convert(_ value: Double, pid: OBDPID, settings: AppSettings) -> Double {
        switch pid {
        case .vehicleSpeed:
            return settings.speedUnit.convert(fromKmh: value)
        case .coolantTemp, .intakeAirTemp, .ambientAirTemp:
            return settings.temperatureUnit.convert(fromCelsius: value)
        default:
            return value
        }
    }

    static func unit(for pid: OBDPID, settings: AppSettings) -> String {
        switch pid {
        case .vehicleSpeed: return settings.speedUnit.symbol
        case .coolantTemp, .intakeAirTemp, .ambientAirTemp: return settings.temperatureUnit.symbol
        default: return metricUnit(for: pid)
        }
    }

    /// The unit a value is stored in, which is what the CSV log records.
    static func metricUnit(for pid: OBDPID) -> String {
        switch pid {
        case .vehicleSpeed: return "km/h"
        case .engineRPM: return "rpm"
        case .coolantTemp, .intakeAirTemp, .ambientAirTemp: return "°C"
        case .controlModuleVoltage, .oxygenSensor1: return "V"
        case .engineLoad, .throttlePosition, .fuelTankLevel, .shortFuelTrim1, .longFuelTrim1: return "%"
        case .mafAirFlow: return "g/s"
        case .engineFuelRate: return "L/h"
        case .engineRuntime: return "s"
        case .timingAdvance: return "°"
        case .monitorStatus: return ""
        }
    }

    static func decimals(for pid: OBDPID) -> Int {
        switch pid {
        case .oxygenSensor1: return 3
        case .controlModuleVoltage, .mafAirFlow, .engineFuelRate, .timingAdvance,
             .shortFuelTrim1, .longFuelTrim1, .fuelTankLevel, .engineLoad, .throttlePosition:
            return 1
        default:
            return 0
        }
    }

    static func format(_ value: Double, pid: OBDPID, settings: AppSettings) -> String {
        return String(format: "%.\(decimals(for: pid))f", convert(value, pid: pid, settings: settings))
    }
}
