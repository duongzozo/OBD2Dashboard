import Foundation

/// Serializes every AT/PID command over a single `BluetoothTransport` —
/// exactly one request in flight at a time (spec §9/§11: "Không gửi lệnh
/// OBD song song khi adapter chỉ hỗ trợ một request tại một thời điểm").
/// Runs entirely on a background queue so Bluetooth I/O never touches the
/// main thread.
final class OBDRequestQueue {
    enum RequestError: Error {
        case timeout
    }

    typealias Completion = (Result<String, RequestError>) -> Void

    private struct PendingRequest {
        let command: String
        let timeoutMs: Int
        let completion: Completion
    }

    private let transport: BluetoothTransport
    private let serialQueue = DispatchQueue(label: "com.diy.obd2dashboard.obdqueue")
    private var pending: [PendingRequest] = []
    private var active: PendingRequest?
    private var activeToken = 0
    private var responseBuffer = ""

    init(transport: BluetoothTransport) {
        self.transport = transport
        transport.onDataReceived = { [weak self] data in
            self?.serialQueue.async { self?.handleIncoming(data) }
        }
    }

    func enqueue(_ command: String, timeoutMs: Int = 2000, completion: @escaping Completion) {
        serialQueue.async {
            self.pending.append(PendingRequest(command: command, timeoutMs: timeoutMs, completion: completion))
            self.startNextIfIdle()
        }
    }

    private func startNextIfIdle() {
        guard active == nil, !pending.isEmpty else { return }
        let next = pending.removeFirst()
        active = next
        activeToken += 1
        let token = activeToken
        responseBuffer = ""

        transport.send((next.command + "\r").data(using: .ascii) ?? Data())

        serialQueue.asyncAfter(deadline: .now() + .milliseconds(next.timeoutMs)) { [weak self] in
            self?.finish(token: token, result: .failure(.timeout))
        }
    }

    private func handleIncoming(_ data: Data) {
        guard let chunk = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8) else { return }
        responseBuffer += chunk
        // ELM327 always ends a reply with the `>` command prompt.
        guard responseBuffer.contains(">") else { return }
        finish(token: activeToken, result: .success(responseBuffer))
    }

    private func finish(token: Int, result: Result<String, RequestError>) {
        guard token == activeToken, let request = active else { return }
        active = nil
        request.completion(result)
        startNextIfIdle()
    }
}
