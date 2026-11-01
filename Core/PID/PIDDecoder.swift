import Foundation

/// Pure Mode 01 PID decoding — no Bluetooth, no state, just bytes in,
/// physical value out. Fully unit-testable with the standard OBD-II
/// formulas; same math every ELM327/OBD-II reference uses.
struct PIDDecoder {
    /// `bytes` must be exactly the A/B/C/D data bytes (the response with
    /// the `41 <PID>` header already stripped) — see
    /// `OBDResponseParser.dataBytes(fromResponse:expectedPID:)`.
    static func decode(pid: OBDPID, bytes: [UInt8]) -> Double? {
        guard bytes.count >= pid.expectedByteCount else { return nil }
        let a = Double(bytes[0])
        let b = bytes.count > 1 ? Double(bytes[1]) : 0

        switch pid {
        case .monitorStatus:
            // Bitmask (MIL status + DTC count), not a single scalar value —
            // handled by the diagnostic module, not telemetry decoding.
            return nil
        case .engineLoad:
            return a * 100.0 / 255.0
        case .coolantTemp:
            return a - 40.0
        case .shortFuelTrim1, .longFuelTrim1:
            return (a - 128.0) * 100.0 / 128.0
        case .engineRPM:
            return ((a * 256.0) + b) / 4.0
        case .vehicleSpeed:
            return a
        case .timingAdvance:
            return (a / 2.0) - 64.0
        case .intakeAirTemp:
            return a - 40.0
        case .mafAirFlow:
            return ((a * 256.0) + b) / 100.0
        case .throttlePosition:
            return a * 100.0 / 255.0
        case .oxygenSensor1:
            return a / 200.0
        case .engineRuntime:
            return (a * 256.0) + b
        case .fuelTankLevel:
            return a * 100.0 / 255.0
        case .controlModuleVoltage:
            return ((a * 256.0) + b) / 1000.0
        case .ambientAirTemp:
            return a - 40.0
        case .engineFuelRate:
            return ((a * 256.0) + b) / 20.0
        }
    }

    /// Parses the 32-bit supported-PID bitmap from a `41 00/20/40/60 A B C D`
    /// response into a set of the PIDs this ECU actually supports among
    /// the ones the app knows about.
    static func supportedPIDs(fromBitmapBytes bytes: [UInt8], queryPID: UInt8) -> Set<OBDPID> {
        guard bytes.count == 4 else { return [] }
        let bitmap: UInt32 = bytes.reduce(0) { ($0 << 8) | UInt32($1) }
        var supported: Set<OBDPID> = []
        for pid in OBDPID.allCases where pid.bitmapQueryPID == queryPID {
            if (bitmap >> pid.bitmapBitIndex) & 1 == 1 {
                supported.insert(pid)
            }
        }
        return supported
    }
}
