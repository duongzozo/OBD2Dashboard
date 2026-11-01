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
    static func hexBytes(fromLine line: String) -> [UInt8]? {
        let tokens = line.split(separator: " ").map(String.init)
        var bytes: [UInt8] = []
        for token in tokens {
            guard token.count == 2, let byte = UInt8(token, radix: 16) else { return nil }
            bytes.append(byte)
        }
        return bytes.isEmpty ? nil : bytes
    }

    /// Collapses a raw ELM327 reply (which may include the command echo,
    /// `SEARCHING...`, blank lines, and the trailing `>` prompt) down to
    /// the single meaningful response line.
    static func extractResponseLine(from raw: String) -> String {
        let lines = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != ">" && !$0.uppercased().contains("SEARCHING") }
        return lines.last ?? ""
    }

    static func mode01DataBytes(fromResponse raw: String, expectedPID: OBDPID) throws -> [UInt8] {
        let line = extractResponseLine(from: raw).uppercased()
        if line.contains("NO DATA") { throw OBDResponseError.noData }
        if line.contains("UNABLE TO CONNECT") { throw OBDResponseError.unableToConnect }
        if line.contains("?") { throw OBDResponseError.malformed(line) }

        guard let bytes = hexBytes(fromLine: line), bytes.count >= 2 else {
            throw OBDResponseError.malformed(line)
        }
        guard bytes[0] == 0x41 else { throw OBDResponseError.malformed(line) }
        guard bytes[1] == expectedPID.rawValue else { throw OBDResponseError.unsupportedPID }
        return Array(bytes.dropFirst(2))
    }

    static func supportedPIDBitmapBytes(fromResponse raw: String, queryPID: UInt8) throws -> [UInt8] {
        let line = extractResponseLine(from: raw).uppercased()
        if line.contains("NO DATA") { throw OBDResponseError.noData }
        guard let bytes = hexBytes(fromLine: line), bytes.count >= 6 else {
            throw OBDResponseError.malformed(line)
        }
        guard bytes[0] == 0x41, bytes[1] == queryPID else { throw OBDResponseError.malformed(line) }
        return Array(bytes[2..<6])
    }
}
