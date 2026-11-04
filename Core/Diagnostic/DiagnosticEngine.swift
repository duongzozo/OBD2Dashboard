import Foundation

enum DTCStatus: Equatable {
    case stored, pending, permanent
}

struct DTCEntry: Equatable {
    var code: String
    var status: DTCStatus
}

/// Mode 03/07/0A scan and Mode 04 clear, over the same `OBDRequestQueue`
/// pattern as `OBDEngine`. Never clears without being told to — the
/// confirm-before-clear dialog and re-read-to-verify flow live in
/// `DiagnosticViewController`; this engine just executes exactly the
/// request it's asked for (spec §7: "Không tự động xóa lỗi").
final class DiagnosticEngine {
    private let queue: OBDRequestQueue

    init(queue: OBDRequestQueue = .shared) {
        self.queue = queue
    }

    func scanStored(completion: @escaping ([DTCEntry]) -> Void) {
        request("03", status: .stored, completion: completion)
    }

    func scanPending(completion: @escaping ([DTCEntry]) -> Void) {
        request("07", status: .pending, completion: completion)
    }

    func scanPermanent(completion: @escaping ([DTCEntry]) -> Void) {
        request("0A", status: .permanent, completion: completion)
    }

    /// Clears DTCs via Mode 04. Caller must already have shown the
    /// confirm-before-clear warning — see spec §7.
    func clearDTCs(completion: @escaping (Bool) -> Void) {
        queue.enqueue("04", timeoutMs: 3000) { result in
            DispatchQueue.main.async {
                completion((try? result.get()) != nil)
            }
        }
    }

    private func request(_ command: String, status: DTCStatus, completion: @escaping ([DTCEntry]) -> Void) {
        queue.enqueue(command, timeoutMs: 3000) { result in
            guard case .success(let response) = result else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let line = OBDResponseParser.extractResponseLine(from: response)
            guard let bytes = OBDResponseParser.hexBytes(fromLine: line), bytes.count > 1 else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            // First byte is the mode-response echo (43/47/4A); the rest are DTC pairs.
            let codes = DTCParser.parse(bytes: Array(bytes.dropFirst(1)))
            let entries = codes.map { DTCEntry(code: $0, status: status) }
            DispatchQueue.main.async { completion(entries) }
        }
    }
}
