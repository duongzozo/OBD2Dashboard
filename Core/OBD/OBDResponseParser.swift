import Foundation

/// Pure parsing of raw ELM327 response text — no I/O. Strips echo/prompt
/// noise, validates the `41 <PID>` response header, and hands back just
/// the data bytes for `PIDDecoder`. Separated from `PIDDecoder` so each is
/// independently unit-testable per spec §15 ("OBD response parser" is
/// listed as its own test target, distinct from "PID decoder").
enum OBDResponseError: Error, Equatable {
    case noData
    case unableToConnect
    case malformed(String)
    case unsupportedPID
}

struct OBDResponseParser {
    /// Accepts bytes with or without separating spaces. `ELM327Initializer`
    /// sends `ATS0`, so a real adapter replies `410C1AF8`, not `41 0C 1A F8`.
    static func hexBytes(fromLine line: String) -> [UInt8]? {
        let digits = Array(line.filter { !$0.isWhitespace })
        guard !digits.isEmpty, digits.count % 2 == 0, digits.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        var bytes: [UInt8] = []
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let byte = UInt8(String(digits[index...index + 1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        return bytes
    }

    /// Every meaningful line of a raw reply, with the prompt, blank lines and
    /// `SEARCHING...` removed. A vehicle with several ECUs answers on several
    /// lines, so callers must not assume there is only one.
    static func responseLines(from raw: String) -> [String] {
        return raw
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "SEARCHING...", with: "\n", options: .caseInsensitive)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.uppercased().contains("SEARCHING") }
    }

    /// Collapses a raw ELM327 reply down to its last meaningful line.
    static func extractResponseLine(from raw: String) -> String {
        return responseLines(from: raw).last ?? ""
    }

    /// A raw reply made readable for the on-device log.
    static func printable(_ raw: String) -> String {
        return raw.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
    }

    static func mode01DataBytes(fromResponse raw: String, expectedPID: OBDPID) throws -> [UInt8] {
        let lines = responseLines(from: raw).map { $0.uppercased() }
        let parsed = lines.compactMap { hexBytes(fromLine: $0) }

        let match = parsed.first { $0.count >= 2 && $0[0] == 0x41 && $0[1] == expectedPID.rawValue }
        if let match = match {
            return Array(match.dropFirst(2))
        }

        try throwIfAdapterReportedError(lines)
        if parsed.contains(where: { $0.count >= 2 && $0[0] == 0x41 }) {
            throw OBDResponseError.unsupportedPID
        }
        throw OBDResponseError.malformed(lines.last ?? "")
    }

    /// Merges the bitmap from every ECU that answered: a PID counts as
    /// supported if any of them reports it.
    static func supportedPIDBitmapBytes(fromResponse raw: String, queryPID: UInt8) throws -> [UInt8] {
        let lines = responseLines(from: raw).map { $0.uppercased() }
        var merged: [UInt8]?
        for bytes in lines.compactMap({ hexBytes(fromLine: $0) }) {
            guard bytes.count >= 6, bytes[0] == 0x41, bytes[1] == queryPID else { continue }
            let bitmap = Array(bytes[2..<6])
            merged = merged.map { zip($0, bitmap).map { $0 | $1 } } ?? bitmap
        }
        if let merged = merged {
            return merged
        }

        try throwIfAdapterReportedError(lines)
        throw OBDResponseError.malformed(lines.last ?? "")
    }

    private static func throwIfAdapterReportedError(_ lines: [String]) throws {
        if lines.contains(where: { $0.contains("NO DATA") }) { throw OBDResponseError.noData }
        if lines.contains(where: { $0.contains("UNABLE TO CONNECT") }) { throw OBDResponseError.unableToConnect }
        if let line = lines.first(where: { $0.contains("?") }) { throw OBDResponseError.malformed(line) }
    }
}
