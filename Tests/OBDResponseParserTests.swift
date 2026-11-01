import XCTest
@testable import OBD2Dashboard

final class OBDResponseParserTests: XCTestCase {
    func testMode01DataBytesStripsPromptAndHeader() throws {
        let raw = "41 0C 1A F8\r\r>"
        let bytes = try OBDResponseParser.mode01DataBytes(fromResponse: raw, expectedPID: .engineRPM)
        XCTAssertEqual(bytes, [0x1A, 0xF8])
    }

    func testMode01DataBytesHandlesEchoAndSearching() throws {
        let raw = "010C\rSEARCHING...\r41 0C 00 00\r\r>"
        let bytes = try OBDResponseParser.mode01DataBytes(fromResponse: raw, expectedPID: .engineRPM)
        XCTAssertEqual(bytes, [0x00, 0x00])
    }

    func testMode01DataBytesThrowsNoData() {
        XCTAssertThrowsError(try OBDResponseParser.mode01DataBytes(fromResponse: "NO DATA\r>", expectedPID: .engineRPM)) { error in
            XCTAssertEqual(error as? OBDResponseError, .noData)
        }
    }

    func testMode01DataBytesThrowsOnPIDMismatch() {
        // Response claims PID 0D (speed) while caller expected PID 0C (RPM).
        XCTAssertThrowsError(try OBDResponseParser.mode01DataBytes(fromResponse: "41 0D 5A\r>", expectedPID: .engineRPM)) { error in
            XCTAssertEqual(error as? OBDResponseError, .unsupportedPID)
        }
    }

    func testSupportedPIDBitmapBytes() throws {
        let raw = "41 00 BE 3E B8 11\r>"
        let bytes = try OBDResponseParser.supportedPIDBitmapBytes(fromResponse: raw, queryPID: 0x00)
        XCTAssertEqual(bytes, [0xBE, 0x3E, 0xB8, 0x11])
    }

    func testExtractResponseLineIgnoresBlankAndPrompt() {
        let line = OBDResponseParser.extractResponseLine(from: "\r\n41 05 7B\r\n>\r\n")
        XCTAssertEqual(line, "41 05 7B")
    }
}
