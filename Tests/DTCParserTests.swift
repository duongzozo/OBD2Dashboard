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

    func testCANReplySkipsCountByte() throws {
        // 43, two codes: P0300, P0171. Reading the count as data gives wrong codes.
        XCTAssertEqual(try DTCParser.codes(fromResponse: "430203000171\r\r>", responseMode: 0x43), ["P0300", "P0171"])
    }

    func testCANReplyWithNoCodes() throws {
        XCTAssertEqual(try DTCParser.codes(fromResponse: "4300\r\r>", responseMode: 0x43), [])
    }

    func testOlderProtocolReplyHasNoCountByte() throws {
        XCTAssertEqual(try DTCParser.codes(fromResponse: "43030001710000\r\r>", responseMode: 0x43), ["P0300", "P0171"])
    }

    func testMultiFrameCANReplyIsReassembledAndTrimmed() throws {
        let raw = "00A\r0:43040300017101\r1:02010300000000\r\r>"
        XCTAssertEqual(try DTCParser.codes(fromResponse: raw, responseMode: 0x43), ["P0300", "P0171", "P0102", "P0103"])
    }

    func testRepliesFromTwoECUsAreCombinedWithoutDuplicates() throws {
        let raw = "43010300\r43020300 0171\r\r>"
        XCTAssertEqual(try DTCParser.codes(fromResponse: raw, responseMode: 0x43), ["P0300", "P0171"])
    }

    func testNoDataMeansNoCodes() throws {
        XCTAssertEqual(try DTCParser.codes(fromResponse: "NO DATA\r\r>", responseMode: 0x43), [])
    }

    func testFailureIsNotReportedAsNoCodes() {
        XCTAssertThrowsError(try DTCParser.codes(fromResponse: "UNABLE TO CONNECT\r\r>", responseMode: 0x43))
        XCTAssertThrowsError(try DTCParser.codes(fromResponse: "?\r\r>", responseMode: 0x43))
    }

    func testEmptyBytesReturnsEmpty() {
        XCTAssertEqual(DTCParser.parse(bytes: []), [])
    }
}
