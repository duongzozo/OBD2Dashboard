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
    /// A scan that could not complete. Kept apart from an empty result: "the
    /// read failed" must never be shown to the driver as "no faults".
    struct ScanError: Error {
        let message: String
    }

    private let queue: OBDRequestQueue

    init(queue: OBDRequestQueue = .shared) {
        self.queue = queue
    }

    func scanStored(completion: @escaping (Result<[DTCEntry], ScanError>) -> Void) {
        request("03", responseMode: 0x43, status: .stored, completion: completion)
    }

    func scanPending(completion: @escaping (Result<[DTCEntry], ScanError>) -> Void) {
        request("07", responseMode: 0x47, status: .pending, completion: completion)
    }

    func scanPermanent(completion: @escaping (Result<[DTCEntry], ScanError>) -> Void) {
        request("0A", responseMode: 0x4A, status: .permanent, completion: completion)
    }

    /// Clears DTCs via Mode 04. Caller must already have shown the
    /// confirm-before-clear warning — see spec §7. Succeeds only on the
    /// positive `44` reply: the ECU can refuse, for example with the engine running.
    func clearDTCs(completion: @escaping (Bool) -> Void) {
        queue.enqueue("04", timeoutMs: 5000) { result in
            let confirmed: Bool
            if case .success(let response) = result {
                confirmed = OBDResponseParser.messages(fromResponse: response).contains { $0.first == 0x44 }
            } else {
                confirmed = false
            }
            DispatchQueue.main.async { completion(confirmed) }
        }
    }

    private func request(_ command: String, responseMode: UInt8, status: DTCStatus,
                         completion: @escaping (Result<[DTCEntry], ScanError>) -> Void) {
        queue.enqueue(command, timeoutMs: 5000) { result in
            let outcome: Result<[DTCEntry], ScanError>
            switch result {
            case .failure:
                outcome = .failure(ScanError(message: "No reply from the adapter. Check that the ECU status is ECU READY."))
            case .success(let response):
                do {
                    let codes = try DTCParser.codes(fromResponse: response, responseMode: responseMode)
                    outcome = .success(codes.map { DTCEntry(code: $0, status: status) })
                } catch {
                    outcome = .failure(ScanError(message: "Unexpected reply: \(OBDResponseParser.printable(response))"))
                }
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }
}
