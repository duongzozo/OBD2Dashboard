import XCTest
@testable import OBD2Dashboard

final class DTCParserTests: XCTestCase {
    func testParsesSinglePowertrainCode() {
        // P0300: letter bits 00 (P), digit1=0, digit2=3, digit3=0, digit4=0
        let bytes: [UInt8] = [0x03, 0x00]
        XCTAssertEqual(DTCParser.parse(bytes: bytes), ["P0300"])
    }

    func testParsesChassisCode() {
        // C1234: letter bits 01 (C), digit1=1, digit2=2 -> byte1=0x52; digit3=3, digit4=4 -> byte2=0x34
        let bytes: [UInt8] = [0x52, 0x34]
        XCTAssertEqual(DTCParser.parse(bytes: bytes), ["C1234"])
    }

    func testSkipsZeroPadding() {
        let bytes: [UInt8] = [0x03, 0x00, 0x00, 0x00]
        XCTAssertEqual(DTCParser.parse(bytes: bytes), ["P0300"])
    }

    func testParsesMultipleCodes() {
        let bytes: [UInt8] = [0x03, 0x00, 0x01, 0x71] // P0300, P0171
        XCTAssertEqual(DTCParser.parse(bytes: bytes), ["P0300", "P0171"])
    }

    func testEmptyBytesReturnsEmpty() {
        XCTAssertEqual(DTCParser.parse(bytes: []), [])
    }
}
