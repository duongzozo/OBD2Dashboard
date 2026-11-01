import XCTest
@testable import OBD2Dashboard

/// Phase 1 smoke test proving the XcodeGen test target/scheme actually
/// wires up and runs. The full suite (PID decoder, fuel calc, DTC parser,
/// etc. per spec section 15) lands alongside those engines in later phases.
final class VehicleProfileTests: XCTestCase {
    func testFordEscapeDefaultIsGasolineWithExpectedAFR() {
        let profile = VehicleProfile.fordEscape2009XLT
        XCTAssertEqual(profile.fuelType, .gasoline)
        XCTAssertEqual(profile.airFuelRatio, 14.7, accuracy: 0.001)
        XCTAssertEqual(profile.drivetrain, .fourWD)
    }

    func testAppSettingsRoundTripsThroughJSON() throws {
        let original = AppSettings.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSpeedUnitConversionToMph() {
        XCTAssertEqual(SpeedUnit.mph.convert(fromKmh: 100), 62.1371, accuracy: 0.01)
    }
}
