import Foundation

/// Decodes the standard 2-byte-per-code DTC bit-packing used by Mode 03
/// (stored), 07 (pending), and 0A (permanent) responses into strings like
/// "P0300". Pure function, no I/O — independently unit-testable per spec
/// §15 ("DTC parser").
struct DTCParser {
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
