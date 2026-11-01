import Foundation

/// Runs the exact adapter init sequence from spec §5 (`ATZ, ATE0, ATL0,
/// ATS0, ATH0, ATSP0, 0100`), then reads the Mode 01 supported-PID bitmap
/// so `OBDEngine` only ever polls PIDs this specific ECU actually reports
/// — never assuming the full table is supported.
final class ELM327Initializer {
    enum InitError: Error {
        case adapterNotResponding
        case ecuNotResponding
    }

    private let queue: OBDRequestQueue

    init(queue: OBDRequestQueue) {
        self.queue = queue
    }

    func initialize(completion: @escaping (Result<Set<OBDPID>, InitError>) -> Void) {
        let setupCommands = ["ATZ", "ATE0", "ATL0", "ATS0", "ATH0", "ATSP0"]
        runSequence(setupCommands, index: 0) { [weak self] success in
            guard success else {
                completion(.failure(.adapterNotResponding))
                return
            }
            self?.detectSupportedPIDs(completion: completion)
        }
    }

    private func runSequence(_ commands: [String], index: Int, completion: @escaping (Bool) -> Void) {
        guard index < commands.count else {
            completion(true)
            return
        }
        queue.enqueue(commands[index], timeoutMs: 3000) { [weak self] result in
            switch result {
            case .success(let response):
                // AT commands don't share one universal positive-response
                // format (OK / ELM327 vX.X / etc.) — treat anything that
                // isn't an explicit ERROR as success.
                if response.uppercased().contains("ERROR") {
                    completion(false)
                } else {
                    self?.runSequence(commands, index: index + 1, completion: completion)
                }
            case .failure:
                completion(false)
            }
        }
    }

    private func detectSupportedPIDs(completion: @escaping (Result<Set<OBDPID>, InitError>) -> Void) {
        queue.enqueue("0100", timeoutMs: 3000) { result in
            switch result {
            case .success(let response):
                guard let bytes = try? OBDResponseParser.supportedPIDBitmapBytes(fromResponse: response, queryPID: 0x00) else {
                    completion(.failure(.ecuNotResponding))
                    return
                }
                completion(.success(PIDDecoder.supportedPIDs(fromBitmapBytes: bytes, queryPID: 0x00)))
            case .failure:
                completion(.failure(.ecuNotResponding))
            }
        }
    }
}
