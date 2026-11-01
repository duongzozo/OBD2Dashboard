import XCTest
@testable import OBD2Dashboard

final class FuelConsumptionEngineTests: XCTestCase {
    private let profile = VehicleProfile.fordEscape2009XLT // AFR 14.7, density 745 g/L

    func testPrefersECUFuelRateWhenAvailable() throws {
        var snapshot = TelemetrySnapshot.empty
        snapshot.engineFuelRateLitersPerHour = .ecuReported(5.0)
        snapshot.vehicleSpeedKmh = .ecuReported(100)

        let result = try XCTUnwrap(FuelConsumptionEngine.compute(snapshot: snapshot, profile: profile))
        XCTAssertEqual(result.source, .ecuReported)
        XCTAssertTrue(result.isPer100km)
        XCTAssertEqual(result.value, 5.0, accuracy: 0.001) // 5 L/h * 100 / 100 km/h = 5 L/100km
    }

    func testFallsBackToMAFCalculationWhenNoECURate() throws {
        var snapshot = TelemetrySnapshot.empty
        snapshot.mafGramsPerSec = .ecuReported(10.0)
        snapshot.vehicleSpeedKmh = .ecuReported(100)

        let result = try XCTUnwrap(FuelConsumptionEngine.compute(snapshot: snapshot, profile: profile))
        XCTAssertEqual(result.source, .calculated)
        // fuelRateLph = 10 * 3600 / (14.7 * 745) = 3.299...
        XCTAssertEqual(result.value / 100.0 * 100.0, result.value, accuracy: 0.0001) // sanity: no NaN
        XCTAssertTrue(result.value > 0)
    }

    func testReturnsLitersPerHourNearZeroSpeed() throws {
        var snapshot = TelemetrySnapshot.empty
        snapshot.engineFuelRateLitersPerHour = .ecuReported(0.8)
        snapshot.vehicleSpeedKmh = .ecuReported(0)

        let result = try XCTUnwrap(FuelConsumptionEngine.compute(snapshot: snapshot, profile: profile))
        XCTAssertFalse(result.isPer100km)
        XCTAssertEqual(result.value, 0.8, accuracy: 0.001)
    }

    func testReturnsNilWhenNoUsableData() {
        let snapshot = TelemetrySnapshot.empty
        XCTAssertNil(FuelConsumptionEngine.compute(snapshot: snapshot, profile: profile))
    }

    func testReturnsNilWhenMAFIsZero() {
        var snapshot = TelemetrySnapshot.empty
        snapshot.mafGramsPerSec = .ecuReported(0)
        snapshot.vehicleSpeedKmh = .ecuReported(50)
        XCTAssertNil(FuelConsumptionEngine.compute(snapshot: snapshot, profile: profile))
    }
}
