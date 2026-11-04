import XCTest
@testable import OBD2Dashboard

final class LiveDataTests: XCTestCase {
    func testFormatConvertsToTheDisplayUnits() {
        var settings = AppSettings()
        settings.speedUnit = .mph
        settings.temperatureUnit = .fahrenheit

        XCTAssertEqual(PIDDisplay.format(100, pid: .vehicleSpeed, settings: settings), "62")
        XCTAssertEqual(PIDDisplay.format(100, pid: .coolantTemp, settings: settings), "212")
        XCTAssertEqual(PIDDisplay.unit(for: .vehicleSpeed, settings: settings), "mph")
        XCTAssertEqual(PIDDisplay.unit(for: .ambientAirTemp, settings: settings), "°F")
    }

    func testFormatLeavesOtherPIDsUnconverted() {
        let settings = AppSettings()
        XCTAssertEqual(PIDDisplay.format(13.84, pid: .controlModuleVoltage, settings: settings), "13.8")
        XCTAssertEqual(PIDDisplay.format(850, pid: .engineRPM, settings: settings), "850")
    }

    func testEveryMeasuredPIDMapsToASnapshotField() {
        var snapshot = TelemetrySnapshot.empty
        snapshot.engineRpm = .ecuReported(850)
        XCTAssertEqual(snapshot.value(for: .engineRPM)?.value, 850)
        XCTAssertNil(snapshot.value(for: .coolantTemp))
        XCTAssertFalse(PIDDisplay.measuredPIDs.contains(.monitorStatus))
        XCTAssertEqual(PIDDisplay.measuredPIDs.count, OBDPID.allCases.count - 1)
    }

    func testCSVLoggerWritesHeaderAndSamples() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logger = TelemetryCSVLogger(directory: directory)
        try logger.start()
        XCTAssertTrue(logger.isRecording)

        var snapshot = TelemetrySnapshot.empty
        snapshot.engineRpm = .ecuReported(850)
        logger.append(snapshot)
        logger.append(TelemetrySnapshot.empty)

        let file = try XCTUnwrap(logger.stop())
        XCTAssertFalse(logger.isRecording)
        XCTAssertEqual(logger.sampleCount, 2)

        let lines = try String(contentsOf: file).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("timestamp,"))
        // The comma in this name must not split the column.
        XCTAssertTrue(lines[0].contains("\"Oxygen Sensor (Bank 1, Sensor 1) (V)\""))
        XCTAssertTrue(lines[1].contains("850.000"))
        // A missing reading stays empty rather than becoming a false zero.
        XCTAssertEqual(lines[2].components(separatedBy: ",").count, PIDDisplay.measuredPIDs.count + 1)
    }

    func testAppendBeforeStartWritesNothing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logger = TelemetryCSVLogger(directory: directory)
        logger.append(TelemetrySnapshot.empty)
        XCTAssertEqual(logger.sampleCount, 0)
    }

    func testFuelRateFallsBackToMAFWhenECUHasNoPID5E() throws {
        let profile = VehicleProfile.fordEscape2009XLT
        var snapshot = TelemetrySnapshot.empty
        snapshot.mafGramsPerSec = .ecuReported(10)

        let rate = try XCTUnwrap(FuelConsumptionEngine.fuelRate(snapshot: snapshot, profile: profile))
        let expected = 10 * 3600.0 / (profile.airFuelRatio * profile.fuelDensityGramsPerLiter)
        XCTAssertEqual(rate.litersPerHour, expected, accuracy: 0.001)
        XCTAssertEqual(rate.source, .calculated)
    }

    func testFuelRatePrefersECUValue() throws {
        var snapshot = TelemetrySnapshot.empty
        snapshot.mafGramsPerSec = .ecuReported(10)
        snapshot.engineFuelRateLitersPerHour = .ecuReported(2.5)

        let rate = try XCTUnwrap(FuelConsumptionEngine.fuelRate(snapshot: snapshot, profile: .fordEscape2009XLT))
        XCTAssertEqual(rate.litersPerHour, 2.5)
        XCTAssertEqual(rate.source, .ecuReported)
    }
}
