import Foundation

/// Serializes every AT/PID command over a single `BluetoothTransport` —
/// exactly one request in flight at a time (spec §9/§11: "Không gửi lệnh
/// OBD song song khi adapter chỉ hỗ trợ một request tại một thời điểm").
/// Runs entirely on a background queue so Bluetooth I/O never touches the
/// main thread.
///
/// Use `shared` in the app: a transport has one `onDataReceived` slot, so a
/// second queue on the same transport silently takes every reply away from
/// the first.
final class OBDRequestQueue {
    static let shared = OBDRequestQueue(transport: BluetoothManager.shared.transport)

    enum RequestError: Error {
        case timeout
        case cancelled
    }

    typealias Completion = (Result<String, RequestError>) -> Void

    private struct PendingRequest {
        let command: String
        let timeoutMs: Int
        let completion: Completion
    }

    /// How long to ignore the adapter after a timeout. A reply that arrives
    /// late must not be mistaken for the answer to the next command.
    private static let settleAfterTimeoutMs = 300

    private let transport: BluetoothTransport
    private let serialQueue = DispatchQueue(label: "com.diy.obd2dashboard.obdqueue")
    private var pending: [PendingRequest] = []
    private var active: PendingRequest?
    private var activeToken = 0
    private var responseBuffer = ""
    private var isSettling = false
    private var logsTraffic = false

    init(transport: BluetoothTransport) {
        self.transport = transport
        transport.onDataReceived = { [weak self] data in
            self?.serialQueue.async { self?.handleIncoming(data) }
        }
    }

    func enqueue(_ command: String, timeoutMs: Int = 2000, completion: @escaping Completion) {
        serialQueue.async {
            self.append(PendingRequest(command: command, timeoutMs: timeoutMs, completion: completion))
        }
    }

    /// For periodic polling: skips the request if the same command is still
    /// waiting, so a slow ECU cannot make the queue grow without bound.
    func enqueueIfNotQueued(_ command: String, timeoutMs: Int = 2000, completion: @escaping Completion) {
        serialQueue.async {
            guard self.active?.command != command,
                  !self.pending.contains(where: { $0.command == command }) else { return }
            self.append(PendingRequest(command: command, timeoutMs: timeoutMs, completion: completion))
        }
    }

    /// Cancels everything queued or in flight, e.g. when the link drops.
    func reset() {
        serialQueue.async {
            var cancelled = self.pending
            if let active = self.active {
                cancelled.insert(active, at: 0)
            }
            self.pending = []
            self.active = nil
            self.activeToken += 1
            self.responseBuffer = ""
            self.isSettling = false
            cancelled.forEach { $0.completion(.failure(.cancelled)) }
        }
    }

    /// Writes each command and raw reply to `BLELog`. Left off while polling,
    /// when the volume would push everything else out of the log.
    func setTrafficLogging(_ enabled: Bool) {
        serialQueue.async {
            self.logsTraffic = enabled
        }
    }

    private func append(_ request: PendingRequest) {
        pending.append(request)
        startNextIfIdle()
    }

    private func startNextIfIdle() {
        guard active == nil, !isSettling, !pending.isEmpty else { return }
        let next = pending.removeFirst()
        active = next
        activeToken += 1
        let token = activeToken
        responseBuffer = ""

        if logsTraffic {
            BLELog.shared.log("OBD TX \(next.command)")
        }
        transport.send((next.command + "\r").data(using: .ascii) ?? Data())

        serialQueue.asyncAfter(deadline: .now() + .milliseconds(next.timeoutMs)) { [weak self] in
            self?.finish(token: token, result: .failure(.timeout))
        }
    }

    private func handleIncoming(_ data: Data) {
        // Nothing is waiting: this is a late reply to a request already given up on.
        guard active != nil else { return }

        // Clone adapters can pad replies with NUL or high-bit bytes, which
        // would otherwise make the whole chunk fail to decode.
        responseBuffer += String(decoding: data.filter { $0 > 0 && $0 < 0x80 }, as: UTF8.self)

        // ELM327 always ends a reply with the `>` command prompt.
        guard responseBuffer.contains(">") else { return }
        finish(token: activeToken, result: .success(responseBuffer))
    }

    private func finish(token: Int, result: Result<String, RequestError>) {
        guard token == activeToken, let request = active else { return }
        active = nil

        switch result {
        case .success(let response):
            if logsTraffic {
                BLELog.shared.log("OBD RX \(request.command): \(OBDResponseParser.printable(response))")
            }
            request.completion(result)
            startNextIfIdle()
        case .failure:
            let partial = OBDResponseParser.printable(responseBuffer)
            BLELog.shared.log("OBD timeout \(request.command) after \(request.timeoutMs)ms, partial reply: \"\(partial)\"")
            request.completion(result)
            isSettling = true
            serialQueue.asyncAfter(deadline: .now() + .milliseconds(Self.settleAfterTimeoutMs)) { [weak self] in
                guard let self = self, self.activeToken == token else { return }
                self.isSettling = false
                self.startNextIfIdle()
            }
        }
    }
}
