import Foundation

/// The Mode 01 PID table from the spec (§5). Each case knows its own byte
/// length and physical-unit formula — `OBDEngine` consults
/// `ELM327Initializer`'s supported-PID bitmap before ever polling one of
/// these, so nothing here is requested from an ECU that doesn't support it.
enum OBDPID: UInt8, CaseIterable, Hashable {
    case monitorStatus = 0x01
    case engineLoad = 0x04
    case coolantTemp = 0x05
    case shortFuelTrim1 = 0x06
    case longFuelTrim1 = 0x07
    case engineRPM = 0x0C
    case vehicleSpeed = 0x0D
    case timingAdvance = 0x0E
    case intakeAirTemp = 0x0F
    case mafAirFlow = 0x10
    case throttlePosition = 0x11
    case oxygenSensor1 = 0x14
    case engineRuntime = 0x1F
    case fuelTankLevel = 0x2F
    case controlModuleVoltage = 0x42
    case ambientAirTemp = 0x46
    case engineFuelRate = 0x5E

    var hexString: String { String(format: "%02X", rawValue) }

    /// Number of data bytes (A, B, ...) expected in the `41 <PID> ...` response.
    var expectedByteCount: Int {
        switch self {
        case .monitorStatus, .engineLoad, .coolantTemp, .shortFuelTrim1,
             .longFuelTrim1, .vehicleSpeed, .timingAdvance, .intakeAirTemp,
             .throttlePosition, .fuelTankLevel, .ambientAirTemp:
            return 1
        case .engineRPM, .mafAirFlow, .oxygenSensor1, .engineRuntime,
             .controlModuleVoltage, .engineFuelRate:
            return 2
        }
    }

    var displayName: String {
        switch self {
        case .monitorStatus: return "Monitor Status"
        case .engineLoad: return "Engine Load"
        case .coolantTemp: return "Coolant Temperature"
        case .shortFuelTrim1: return "Short Fuel Trim (Bank 1)"
        case .longFuelTrim1: return "Long Fuel Trim (Bank 1)"
        case .engineRPM: return "Engine RPM"
        case .vehicleSpeed: return "Vehicle Speed"
        case .timingAdvance: return "Timing Advance"
        case .intakeAirTemp: return "Intake Air Temperature"
        case .mafAirFlow: return "MAF Air Flow"
        case .throttlePosition: return "Throttle Position"
        case .oxygenSensor1: return "Oxygen Sensor (Bank 1, Sensor 1)"
        case .engineRuntime: return "Engine Runtime"
        case .fuelTankLevel: return "Fuel Tank Level"
        case .controlModuleVoltage: return "Control Module Voltage"
        case .ambientAirTemp: return "Ambient Air Temperature"
        case .engineFuelRate: return "Engine Fuel Rate"
        }
    }

    /// Which of the four supported-PID bitmap requests (00/20/40/60) covers
    /// this PID, and its bit position within that 32-bit map (bit 31 = the
    /// next PID after the query one, counting down to bit 0 = +0x20).
    var bitmapQueryPID: UInt8 {
        switch rawValue {
        case 0x01...0x20: return 0x00
        case 0x21...0x40: return 0x20
        case 0x41...0x60: return 0x40
        default: return 0x60
        }
    }

    var bitmapBitIndex: Int {
        let offsetBase = bitmapQueryPID
        return Int(offsetBase) + 0x20 - Int(rawValue)
    }
}
