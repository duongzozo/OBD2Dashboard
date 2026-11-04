import Foundation

/// Decodes the standard 2-byte-per-code DTC bit-packing used by Mode 03
/// (stored), 07 (pending), and 0A (permanent) responses into strings like
/// "P0300". Pure function, no I/O — independently unit-testable per spec
/// §15 ("DTC parser").
struct DTCParser {
    /// Decodes a whole adapter reply. `responseMode` is the mode plus 0x40
    /// (0x43 for Mode 03). An adapter answers `NO DATA` when nothing is stored
    /// on some vehicles, so that means "no codes" rather than a failure.
    static func codes(fromResponse raw: String, responseMode: UInt8) throws -> [String] {
        let lines = OBDResponseParser.responseLines(from: raw).map { $0.uppercased() }
        if lines.contains(where: { $0.contains("UNABLE TO CONNECT") }) { throw OBDResponseError.unableToConnect }
        if lines.contains(where: { $0.contains("NO DATA") }) { return [] }

        let messages = OBDResponseParser.messages(fromResponse: raw).filter { $0.first == responseMode }
        guard !messages.isEmpty else { throw OBDResponseError.malformed(lines.last ?? "") }

        var codes: [String] = []
        for message in messages {
            // CAN puts a code count after the mode byte: 43 02 0300 0171, an
            // even total. Older protocols send fixed 7-byte messages with no
            // count: 43 0300 0171 0000, an odd total.
            let hasCount = message.count % 2 == 0
            let payload = Array(message.dropFirst(hasCount ? 2 : 1))
            for code in parse(bytes: payload) where !codes.contains(code) {
                codes.append(code)
            }
        }
        return codes
    }

    static func parse(bytes: [UInt8]) -> [String] {
        var codes: [String] = []
        var index = 0
        while index + 1 < bytes.count {
            let b1 = bytes[index]
            let b2 = bytes[index + 1]
            index += 2
            if b1 == 0 && b2 == 0 { continue } // Padding / unused slot.

            let letter: String
            switch (b1 >> 6) & 0x03 {
            case 0: letter = "P"
            case 1: letter = "C"
            case 2: letter = "B"
            default: letter = "U"
            }
            let digit1 = (b1 >> 4) & 0x03
            let digit2 = b1 & 0x0F
            let digit3 = (b2 >> 4) & 0x0F
            let digit4 = b2 & 0x0F
            let code = String(format: "%@%X%X%X%X", letter, digit1, digit2, digit3, digit4)
            codes.append(code)
        }
        return codes
    }
}
