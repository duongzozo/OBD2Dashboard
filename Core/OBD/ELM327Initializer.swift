import Foundation

/// Runs the exact adapter init sequence from spec §5 (`ATZ, ATE0, ATL0,
/// ATS0, ATH0, ATSP0, 0100`), then reads the Mode 01 supported-PID bitmaps
/// so `OBDEngine` only ever polls PIDs this specific ECU actually reports
/// — never assuming the full table is supported.
final class ELM327Initializer {
    enum InitError: Error, CustomStringConvertible {
        case adapterNotResponding(command: String, detail: String)
        case ecuNotResponding(detail: String)

        var description: String {
            switch self {
            case .adapterNotResponding(let command, let detail):
                return "adapter failed on \(command): \(detail)"
            case .ecuNotResponding(let detail):
                return "ECU did not answer 0100: \(detail)"
            }
        }
    }

    private static let setupCommands: [(command: String, timeoutMs: Int)] = [
        ("ATZ", 5000), ("ATE0", 3000), ("ATL0", 3000), ("ATS0", 3000), ("ATH0", 3000), ("ATSP0", 3000)
    ]

    /// The first request after `ATSP0` also makes the adapter search for the
    /// vehicle's protocol, which takes several seconds on older protocols.
    private static let firstQueryTimeoutMs = 10000
    private static let laterQueryTimeoutMs = 3000
    private static let lastBitmapQueryPID: UInt8 = 0x40

    private let queue: OBDRequestQueue

    init(queue: OBDRequestQueue) {
        self.queue = queue
    }

    func initialize(completion: @escaping (Result<Set<OBDPID>, InitError>) -> Void) {
        runSetup(index: 0) { [weak self] error in
            if let error = error {
                completion(.failure(error))
                return
            }
            self?.detectSupportedPIDs(queryPID: 0x00, supported: [], completion: completion)
        }
    }

    private func runSetup(index: Int, completion: @escaping (InitError?) -> Void) {
        guard index < Self.setupCommands.count else {
            completion(nil)
            return
        }
        let step = Self.setupCommands[index]
        queue.enqueue(step.command, timeoutMs: step.timeoutMs) { [weak self] result in
            switch result {
            case .success(let response):
                // AT commands don't share one universal positive-response
                // format (OK / ELM327 vX.X / etc.) — treat anything that
                // isn't an explicit ERROR as success.
                if response.uppercased().contains("ERROR") {
                    completion(.adapterNotResponding(command: step.command, detail: OBDResponseParser.printable(response)))
                } else {
                    self?.runSetup(index: index + 1, completion: completion)
                }
            case .failure(let error):
                completion(.adapterNotResponding(command: step.command, detail: "\(error)"))
            }
        }
    }

    /// Walks the bitmap chain. The last bit of each bitmap says whether the
    /// next one (0120, 0140) exists, and the app's PIDs above 0x20 — fuel
    /// level, voltage, ambient temperature, fuel rate — are only listed there.
    /// Only 0100 is required: a failure later keeps what is already known.
    private func detectSupportedPIDs(queryPID: UInt8, supported: Set<OBDPID>,
                                     completion: @escaping (Result<Set<OBDPID>, InitError>) -> Void) {
        let isFirstQuery = queryPID == 0x00
        let command = String(format: "01%02X", queryPID)
        let timeoutMs = isFirstQuery ? Self.firstQueryTimeoutMs : Self.laterQueryTimeoutMs

        queue.enqueue(command, timeoutMs: timeoutMs) { [weak self] result in
            do {
                let bytes = try OBDResponseParser.supportedPIDBitmapBytes(fromResponse: result.get(), queryPID: queryPID)
                let merged = supported.union(PIDDecoder.supportedPIDs(fromBitmapBytes: bytes, queryPID: queryPID))
                let hasNextBitmap = bytes[3] & 0x01 == 0x01
                if hasNextBitmap, queryPID < Self.lastBitmapQueryPID {
                    self?.detectSupportedPIDs(queryPID: queryPID + 0x20, supported: merged, completion: completion)
                } else {
                    completion(.success(merged))
                }
            } catch {
                if isFirstQuery {
                    completion(.failure(.ecuNotResponding(detail: "\(error)")))
                } else {
                    BLELog.shared.log("\(command) failed, keeping PIDs found so far: \(error)")
                    completion(.success(supported))
                }
            }
        }
    }
}
