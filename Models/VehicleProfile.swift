import Foundation

/// User-configurable vehicle parameters. The fuel/trip engines must read these
/// values at runtime instead of hardcoding any vehicle-specific constant.
struct VehicleProfile: Codable, Equatable {
    enum FuelType: String, Codable, CaseIterable, Equatable {
        case gasoline
        case diesel
        case ethanolE85
        case lpg

        var displayName: String {
            switch self {
            case .gasoline: return "Gasoline"
            case .diesel: return "Diesel"
            case .ethanolE85: return "Ethanol (E85)"
            case .lpg: return "LPG"
            }
        }

        /// Reasonable default stoichiometric air-fuel ratio, used only as a
        /// starting point — overridable per-profile in Settings.
        var defaultAirFuelRatio: Double {
            switch self {
            case .gasoline: return 14.7
            case .diesel: return 14.5
            case .ethanolE85: return 9.8
            case .lpg: return 15.5
            }
        }

        /// Reasonable default fuel density in g/L, overridable per-profile.
        var defaultFuelDensityGramsPerLiter: Double {
            switch self {
            case .gasoline: return 745.0
            case .diesel: return 832.0
            case .ethanolE85: return 785.0
            case .lpg: return 550.0
            }
        }
    }

    enum Drivetrain: String, Codable, CaseIterable, Equatable {
        case fwd, rwd, awd, fourWD

        var displayName: String {
            switch self {
            case .fwd: return "FWD"
            case .rwd: return "RWD"
            case .awd: return "AWD"
            case .fourWD: return "4WD"
            }
        }
    }

    var name: String
    var make: String
    var model: String
    var modelYear: Int
    var engineDisplacementLiters: Double
    var fuelType: FuelType
    var fuelDensityGramsPerLiter: Double
    var airFuelRatio: Double
    var drivetrain: Drivetrain
    var fuelTankCapacityLiters: Double

    static let fordEscape2009XLT = VehicleProfile(
        name: "Ford Escape XLT",
        make: "Ford",
        model: "Escape XLT",
        modelYear: 2009,
        engineDisplacementLiters: 2.3,
        fuelType: .gasoline,
        fuelDensityGramsPerLiter: FuelType.gasoline.defaultFuelDensityGramsPerLiter,
        airFuelRatio: FuelType.gasoline.defaultAirFuelRatio,
        drivetrain: .fourWD,
        fuelTankCapacityLiters: 60.6
    )
}
