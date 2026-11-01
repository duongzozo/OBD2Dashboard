import XCTest
@testable import OBD2Dashboard

final class TripComputerTests: XCTestCase {
    private func makeTripComputer() -> TripComputer {
        let suiteName = "TripComputerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return TripComputer(defaults: defaults)
    }

    func testFirstUpdateSeedsTimestampWithoutAccumulating() {
        let computer = makeTripComputer()
        var snapshot = TelemetrySnapshot.empty
        snapshot.vehicleSpeedKmh = .simulated(100)
        computer.update(with: snapshot, fuelRateLitersPerHour: 6.0)
        XCTAssertEqual(computer.currentTrip.value.distanceKm, 0)
    }

    func testAccumulatesDistanceAndFuelBetweenTicks() {
        let computer = makeTripComputer()
        let start = Date()

        var first = TelemetrySnapshot.empty
        first.timestamp = start
        first.vehicleSpeedKmh = .simulated(100)
        computer.update(with: first, fuelRateLitersPerHour: 6.0)

        // update() rejects gaps >= 5s (stale/timeout guard), so ticks must
        // be close together — scale expected values to a 1-second tick
        // instead of assuming a full hour elapsed.
        var second = TelemetrySnapshot.empty
        second.timestamp = start.addingTimeInterval(1)
        second.vehicleSpeedKmh = .simulated(100)
        computer.update(with: second, fuelRateLitersPerHour: 6.0)

        XCTAssertEqual(computer.currentTrip.value.distanceKm, 100.0 / 3600.0, accuracy: 0.0001)
        XCTAssertEqual(computer.currentTrip.value.fuelUsedLiters, 6.0 / 3600.0, accuracy: 0.0001)
        XCTAssertEqual(computer.currentTrip.value.elapsedSeconds, 1, accuracy: 0.01)
    }

    func testIgnoresGapsLongerThanFiveSeconds() {
        let computer = makeTripComputer()
        let start = Date()

        var first = TelemetrySnapshot.empty
        first.timestamp = start
        first.vehicleSpeedKmh = .simulated(100)
        computer.update(with: first, fuelRateLitersPerHour: 6.0)

        var second = TelemetrySnapshot.empty
        second.timestamp = start.addingTimeInterval(30) // stale/timeout gap
        second.vehicleSpeedKmh = .simulated(100)
        computer.update(with: second, fuelRateLitersPerHour: 6.0)

        XCTAssertEqual(computer.currentTrip.value.distanceKm, 0)
    }

    func testResetCurrentTripClearsOnlyCurrentTrip() {
        let computer = makeTripComputer()
        let start = Date()
        var first = TelemetrySnapshot.empty
        first.timestamp = start
        first.vehicleSpeedKmh = .simulated(60)
        computer.update(with: first, fuelRateLitersPerHour: 5.0)
        var second = TelemetrySnapshot.empty
        second.timestamp = start.addingTimeInterval(1)
        second.vehicleSpeedKmh = .simulated(60)
        computer.update(with: second, fuelRateLitersPerHour: 5.0)

        computer.resetCurrentTrip()

        XCTAssertEqual(computer.currentTrip.value.distanceKm, 0)
        XCTAssertEqual(computer.sinceReset.value.distanceKm, 60.0 / 3600.0, accuracy: 0.0001)
    }

    func testAverageConsumptionNilUntilMeaningfulDistance() throws {
        var record = TripRecord()
        record.distanceKm = 0.01
        record.fuelUsedLiters = 1.0
        XCTAssertNil(record.averageConsumptionPer100km)

        record.distanceKm = 10
        let average = try XCTUnwrap(record.averageConsumptionPer100km)
        XCTAssertEqual(average, 10, accuracy: 0.01)
    }
}
