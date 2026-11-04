import XCTest
@testable import OBD2Dashboard

/// Scripted adapter that answers like real hardware: no spaces after `ATS0`,
/// replies split across BLE-sized chunks, terminated by the `>` prompt.
private final class ScriptedTransport: BluetoothTransport {
    let state = Observable<ConnectionState>(.connected)
    var onDataReceived: ((Data) -> Void)?
    var replies: [String: String] = [:]
    /// Commands that get no reply until `deliverLate` is called.
    var silentCommands: Set<String> = []
    private var sent: [String] = []
    private let lock = NSLock()
    private let deliveryQueue = DispatchQueue(label: "test.scripted.transport")

    func startScan(onDiscovered: @escaping (DiscoveredPeripheral) -> Void) {}
    func stopScan() {}
    func connect(to peripheralID: String) {}
    func disconnect() {}

    func send(_ data: Data) {
        let command = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
        lock.lock()
        sent.append(command)
        lock.unlock()
        guard !silentCommands.contains(command) else { return }
        deliver(replies[command] ?? "?\r\r>")
    }

    func deliverLate(_ reply: String) {
        deliver(reply)
    }

    var sentCommands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    private func deliver(_ reply: String) {
        let bytes = Array(reply.utf8)
        deliveryQueue.async {
            for start in stride(from: 0, to: bytes.count, by: 20) {
                self.onDataReceived?(Data(bytes[start..<min(start + 20, bytes.count)]))
            }
        }
    }
}

final class ELM327SessionTests: XCTestCase {
    private func realisticReplies() -> [String: String] {
        return [
            "ATZ": "\r\rELM327 v1.5\r\r>",
            "ATE0": "ATE0\rOK\r\r>",
            "ATL0": "OK\r\r>",
            "ATS0": "OK\r\r>",
            "ATH0": "OK\r\r>",
            "ATSP0": "OK\r\r>",
            // 0C and the "next bitmap" bit are set here; 2F in 0120; 42 and 46 in 0140.
            "0100": "SEARCHING...\r4100BE3EB811\r\r>",
            "0120": "412000020001\r\r>",
            "0140": "414044000000\r\r>"
        ]
    }

    private func initialize(_ transport: ScriptedTransport) -> Result<Set<OBDPID>, ELM327Initializer.InitError>? {
        let queue = OBDRequestQueue(transport: transport)
        let initializer = ELM327Initializer(queue: queue)
        let finished = expectation(description: "init finished")
        var outcome: Result<Set<OBDPID>, ELM327Initializer.InitError>?
        initializer.initialize { result in
            outcome = result
            finished.fulfill()
        }
        wait(for: [finished], timeout: 15)
        return outcome
    }

    func testInitSucceedsWithSpacelessRepliesAndWalksBitmapChain() throws {
        let transport = ScriptedTransport()
        transport.replies = realisticReplies()

        let supported = try XCTUnwrap(initialize(transport)).get()

        XCTAssertEqual(transport.sentCommands, ["ATZ", "ATE0", "ATL0", "ATS0", "ATH0", "ATSP0", "0100", "0120", "0140"])
        XCTAssertTrue(supported.contains(.engineRPM))
        XCTAssertTrue(supported.contains(.fuelTankLevel))
        XCTAssertTrue(supported.contains(.controlModuleVoltage))
        XCTAssertTrue(supported.contains(.ambientAirTemp))
    }

    func testInitStopsChainWhenNextBitmapBitIsClear() throws {
        let transport = ScriptedTransport()
        transport.replies = realisticReplies()
        transport.replies["0100"] = "4100BE3EB810\r\r>"

        let supported = try XCTUnwrap(initialize(transport)).get()

        XCTAssertFalse(transport.sentCommands.contains("0120"))
        XCTAssertTrue(supported.contains(.engineRPM))
    }

    func testLaterBitmapFailureKeepsPIDsAlreadyFound() throws {
        let transport = ScriptedTransport()
        transport.replies = realisticReplies()
        transport.replies["0120"] = "NO DATA\r\r>"

        let supported = try XCTUnwrap(initialize(transport)).get()

        XCTAssertTrue(supported.contains(.engineRPM))
        XCTAssertFalse(transport.sentCommands.contains("0140"))
    }

    func testInitReportsUnreachableECUWithTheAdaptersReason() throws {
        let transport = ScriptedTransport()
        transport.replies = realisticReplies()
        transport.replies["0100"] = "SEARCHING...\rUNABLE TO CONNECT\r\r>"

        let result = try XCTUnwrap(initialize(transport))

        guard case .failure(let error) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        XCTAssertTrue(error.description.contains("unableToConnect"), error.description)
    }

    func testLateReplyIsNotGivenToTheNextCommand() {
        let transport = ScriptedTransport()
        transport.replies = ["010C": "410C1AF8\r\r>"]
        transport.silentCommands = ["010D"]
        let queue = OBDRequestQueue(transport: transport)

        let timedOut = expectation(description: "010D timed out")
        queue.enqueue("010D", timeoutMs: 100) { result in
            if case .failure(.timeout) = result {
                // Arrives inside the settle window, after the request was abandoned.
                transport.deliverLate("410D5A\r\r>")
                timedOut.fulfill()
            }
        }

        let answered = expectation(description: "010C answered")
        var response: String?
        queue.enqueue("010C", timeoutMs: 1000) { result in
            response = try? result.get()
            answered.fulfill()
        }

        wait(for: [timedOut, answered], timeout: 5)
        XCTAssertEqual(response, "410C1AF8\r\r>")
    }

    func testEnqueueIfNotQueuedSkipsCommandStillWaiting() {
        let transport = ScriptedTransport()
        transport.silentCommands = ["010C"]
        let queue = OBDRequestQueue(transport: transport)

        let finished = expectation(description: "first request finished")
        var calls = 0
        queue.enqueueIfNotQueued("010C", timeoutMs: 100) { _ in
            calls += 1
            finished.fulfill()
        }
        queue.enqueueIfNotQueued("010C", timeoutMs: 100) { _ in
            calls += 1
        }

        wait(for: [finished], timeout: 5)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(transport.sentCommands, ["010C"])
    }

    func testResetCancelsQueuedAndInFlightRequests() {
        let transport = ScriptedTransport()
        transport.silentCommands = ["0105"]
        let queue = OBDRequestQueue(transport: transport)

        let inFlight = expectation(description: "in-flight cancelled")
        let waiting = expectation(description: "queued cancelled")
        queue.enqueue("0105", timeoutMs: 5000) { result in
            if case .failure(.cancelled) = result { inFlight.fulfill() }
        }
        queue.enqueue("010C", timeoutMs: 5000) { result in
            if case .failure(.cancelled) = result { waiting.fulfill() }
        }
        queue.reset()

        wait(for: [inFlight, waiting], timeout: 2)
    }

    func testResolveWriteTypeFallsBackToWhatTheAdapterSupports() {
        XCTAssertEqual(BLETransport.resolveWriteType(preferred: .withoutResponse, properties: [.write]), .withResponse)
        XCTAssertEqual(BLETransport.resolveWriteType(preferred: .withResponse, properties: [.writeWithoutResponse]), .withoutResponse)
        XCTAssertEqual(BLETransport.resolveWriteType(preferred: .withoutResponse, properties: [.write, .writeWithoutResponse]), .withoutResponse)
        XCTAssertNil(BLETransport.resolveWriteType(preferred: .withResponse, properties: [.notify]))
    }
}
