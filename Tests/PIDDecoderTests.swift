import XCTest
@testable import OBD2Dashboard

final class PIDDecoderTests: XCTestCase {
    func testEngineRPM() throws {
        // 41 0C 1A F8 -> RPM = ((0x1A*256)+0xF8)/4 = 1726
        let value = try XCTUnwrap(PIDDecoder.decode(pid: .engineRPM, bytes: [0x1A, 0xF8]))
        XCTAssertEqual(value, 1726, accuracy: 0.01)
    }

    func testVehicleSpeed() {
        XCTAssertEqual(PIDDecoder.decode(pid: .vehicleSpeed, bytes: [0x5A]), 90)
    }

    func testCoolantTemp() {
        // 41 05 7B -> 0x7B(123) - 40 = 83
        XCTAssertEqual(PIDDecoder.decode(pid: .coolantTemp, bytes: [0x7B]), 83)
    }

    func testControlModuleVoltage() throws {
        // A B -> ((A*256)+B)/1000, e.g. 0x37 0x3A -> (55*256+58)/1000 = 14.138
        let value = try XCTUnwrap(PIDDecoder.decode(pid: .controlModuleVoltage, bytes: [0x37, 0x3A]))
        XCTAssertEqual(value, 14.138, accuracy: 0.001)
    }

    func testThrottlePositionFullyOpen() throws {
        let value = try XCTUnwrap(PIDDecoder.decode(pid: .throttlePosition, bytes: [0xFF]))
        XCTAssertEqual(value, 100, accuracy: 0.01)
    }

    func testEngineFuelRate() throws {
        // A B -> ((A*256)+B)/20
        let value = try XCTUnwrap(PIDDecoder.decode(pid: .engineFuelRate, bytes: [0x00, 0x64]))
        XCTAssertEqual(value, 5.0, accuracy: 0.001)
    }

    func testDecodeReturnsNilWhenNotEnoughBytes() {
        XCTAssertNil(PIDDecoder.decode(pid: .engineRPM, bytes: [0x1A]))
    }

    func testSupportedPIDBitmapParsing() {
        // Bit 20 (0-indexed from LSB) must correspond to PID 0x0C (engine RPM).
        let bitmap: UInt32 = 1 << 20
        let bytes: [UInt8] = [
            UInt8((bitmap >> 24) & 0xFF),
            UInt8((bitmap >> 16) & 0xFF),
            UInt8((bitmap >> 8) & 0xFF),
            UInt8(bitmap & 0xFF)
        ]
        let supported = PIDDecoder.supportedPIDs(fromBitmapBytes: bytes, queryPID: 0x00)
        XCTAssertEqual(supported, [.engineRPM])
    }
}
