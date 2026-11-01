import Foundation

/// A DTC code with its human-readable description and fault group.
struct DTCInfo: Equatable {
    var code: String
    var description: String
    var group: String
}

/// Extensible static description table. Starts with the examples named in
/// spec §7 (P0421, P0300, P0171, P0130); add more entries here as needed
/// without touching `DTCParser`'s decoding logic.
struct DTCLibrary {
    private static let descriptions: [String: (description: String, group: String)] = [
        "P0421": ("Warm Up Catalyst Efficiency Below Threshold (Bank 1)", "Emissions"),
        "P0300": ("Random/Multiple Cylinder Misfire Detected", "Ignition / Misfire"),
        "P0171": ("System Too Lean (Bank 1)", "Fuel / Air Metering"),
        "P0130": ("O2 Sensor Circuit Malfunction (Bank 1, Sensor 1)", "Oxygen Sensor")
    ]

    static func info(for code: String) -> DTCInfo {
        if let entry = descriptions[code] {
            return DTCInfo(code: code, description: entry.description, group: entry.group)
        }
        return DTCInfo(code: code, description: "No description available for this code yet.", group: "Unknown")
    }
}
