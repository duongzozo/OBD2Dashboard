import Foundation

/// Polls the vehicle over `OBDRequestQueue`: speed, RPM and throttle on a fast
/// timer, everything else on a slow one. Every value is an actual ECU
/// round-trip tagged `.ecuReported`, and only for PIDs `ELM327Initializer`
/// confirmed this ECU supports.
final class OBDEngine {
    let ecuState: Observable<ConnectionState> = Observable(.disconnected)
    let supportedPIDs: Observable<Set<OBDPID>> = Observable([])
    let vehicleInfo: Observable<VehicleInfo> = Observable(.unknown)
    var onSnapshotUpdate: ((TelemetrySnapshot) -> Void)?

    private let bluetoothManager: BluetoothManager
    private let queue: OBDRequestQueue
    private let initializer: ELM327Initializer
    private var powerSaveEnabled = SettingsStore.shared.settings.value.powerSaveModeEnabled
    private var fastTimer: Timer?
    private var slowTimer: Timer?
    private var latestSnapshot = TelemetrySnapshot.empty
    /// Bumped by `stop()`, so an init result from an old link is ignored.
    private var sessionGeneration = 0
    /// Last logged result per PID. Only changes are logged, which keeps the
    /// log readable while polling several times a second.
    private var lastPollOutcome: [OBDPID: String] = [:]

    private static let maxInitAttempts = 2
    private static let initRetryDelay: TimeInterval = 1.0
    private static let powerSaveFastInterval: TimeInterval = 0.5
    private static let powerSaveSlowInterval: TimeInterval = 3.0
    private static let fastPIDs: [OBDPID] = [.vehicleSpeed, .engineRPM, .throttlePosition]
    private static let slowPIDs: [OBDPID] = [
        .coolantTemp, .controlModuleVoltage, .fuelTankLevel, .engineFuelRate,
        .mafAirFlow, .ambientAirTemp, .intakeAirTemp, .engineRuntime,
        .shortFuelTrim1, .longFuelTrim1, .timingAdvance, .engineLoad, .oxygenSensor1
    ]

    init(bluetoothManager: BluetoothManager, queue: OBDRequestQueue = .shared) {
        self.bluetoothManager = bluetoothManager
        self.queue = queue
        self.initializer = ELM327Initializer(queue: queue)

        bluetoothManager.connectionState.observe { [weak self] state in
            switch state {
            case .connected:
                self?.beginInitialization(attempt: 1)
            case .disconnected, .error:
                self?.stop()
                self?.ecuState.value = .disconnected
            default:
                break
            }
        }

        SettingsStore.shared.settings.observe { [weak self] settings in
            guard let self = self, settings.powerSaveModeEnabled != self.powerSaveEnabled else { return }
            self.powerSaveEnabled = settings.powerSaveModeEnabled
            if self.fastTimer != nil {
                self.startPolling()
            }
        }
    }

    func stop() {
        sessionGeneration += 1
        stopTimers()
        queue.reset()

        // Stale numbers must not stay on screen as if they were still live.
        latestSnapshot = TelemetrySnapshot()
        onSnapshotUpdate?(latestSnapshot)
        supportedPIDs.value = []
        vehicleInfo.value = .unknown
    }

    private func stopTimers() {
        fastTimer?.invalidate()
        fastTimer = nil
        slowTimer?.invalidate()
        slowTimer = nil
    }

    private func beginInitialization(attempt: Int) {
        let generation = sessionGeneration
        ecuState.value = .initializing
        lastPollOutcome = [:]
        queue.setTrafficLogging(true)
        BLELog.shared.log("ELM327 init attempt \(attempt)/\(Self.maxInitAttempts)")

        initializer.initialize { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.sessionGeneration == generation else { return }
                self.queue.setTrafficLogging(false)
                switch result {
                case .success(let supported):
                    let names = supported.map { $0.hexString }.sorted().joined(separator: ",")
                    BLELog.shared.log("ELM327 ready, supported PIDs: [\(names)]")
                    self.supportedPIDs.value = supported
                    self.ecuState.value = .ecuReady
                    self.fetchVehicleInfo(generation: generation)
                    self.startPolling()
                case .failure(let error):
                    BLELog.shared.log("ELM327 init failed: \(error)")
                    self.retryOrFail(after: attempt, error: error, generation: generation)
                }
            }
        }
    }

    private func retryOrFail(after attempt: Int, error: ELM327Initializer.InitError, generation: Int) {
        guard attempt < Self.maxInitAttempts else {
            ecuState.value = .error("ELM327 init failed: \(error)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initRetryDelay) { [weak self] in
            guard let self = self, self.sessionGeneration == generation else { return }
            self.beginInitialization(attempt: attempt + 1)
        }
    }

    /// Queued ahead of polling, and purely informational: a vehicle that does
    /// not answer just leaves the field empty.
    private func fetchVehicleInfo(generation: Int) {
        requestInfo("ATI") { info, raw in
            info.adapterVersion = OBDResponseParser.responseLines(from: raw).last
        }
        requestInfo("ATDP") { info, raw in
            info.protocolName = OBDResponseParser.responseLines(from: raw).last
        }
        requestInfo("0902") { info, raw in
            info.vin = OBDResponseParser.vin(fromResponse: raw)
        }

        func requestInfo(_ command: String, apply: @escaping (inout VehicleInfo, String) -> Void) {
            queue.enqueue(command, timeoutMs: 3000) { [weak self] result in
                guard case .success(let raw) = result else { return }
                DispatchQueue.main.async {
                    guard let self = self, self.sessionGeneration == generation else { return }
                    var info = self.vehicleInfo.value
                    apply(&info, raw)
                    self.vehicleInfo.value = info
                }
            }
        }
    }

    private func startPolling() {
        stopTimers()
        let settings = SettingsStore.shared.settings.value
        let fastInterval = settings.powerSaveModeEnabled
            ? Self.powerSaveFastInterval
            : max(0.1, Double(settings.dashboardPollingIntervalMs) / 1000.0)
        let slowInterval = settings.powerSaveModeEnabled ? Self.powerSaveSlowInterval : 1.0

        fastTimer = Timer.scheduledTimer(withTimeInterval: fastInterval, repeats: true) { [weak self] _ in
            self?.pollFast()
        }
        slowTimer = Timer.scheduledTimer(withTimeInterval: slowInterval, repeats: true) { [weak self] _ in
            self?.pollSlow()
        }
    }

    private func pollFast() {
        for pid in Self.fastPIDs where supportedPIDs.value.contains(pid) {
            poll(pid)
        }
    }

    private func pollSlow() {
        for pid in Self.slowPIDs where supportedPIDs.value.contains(pid) {
            poll(pid)
        }
    }

    private func poll(_ pid: OBDPID) {
        let timeoutMs = SettingsStore.shared.settings.value.obdRequestTimeoutMs
        queue.enqueueIfNotQueued("01" + pid.hexString, timeoutMs: timeoutMs) { [weak self] result in
            DispatchQueue.main.async {
                self?.handlePollResult(result, for: pid)
            }
        }
    }

    private func handlePollResult(_ result: Result<String, OBDRequestQueue.RequestError>, for pid: OBDPID) {
        do {
            let response = try result.get()
            let bytes = try OBDResponseParser.mode01DataBytes(fromResponse: response, expectedPID: pid)
            guard let value = PIDDecoder.decode(pid: pid, bytes: bytes) else {
                recordPollOutcome("undecodable reply \(OBDResponseParser.printable(response))", for: pid)
                return
            }
            recordPollOutcome("ok", for: pid)
            apply(pid: pid, value: value)
        } catch OBDRequestQueue.RequestError.cancelled {
            return
        } catch {
            recordPollOutcome("\(error)", for: pid)
        }
    }

    private func recordPollOutcome(_ outcome: String, for pid: OBDPID) {
        guard lastPollOutcome[pid] != outcome else { return }
        lastPollOutcome[pid] = outcome
        BLELog.shared.log("PID \(pid.hexString) (\(pid.displayName)): \(outcome)")
    }

    private func apply(pid: OBDPID, value: Double) {
        let tv = TelemetryValue.ecuReported(value)
        switch pid {
        case .vehicleSpeed: latestSnapshot.vehicleSpeedKmh = tv
        case .engineRPM: latestSnapshot.engineRpm = tv
        case .coolantTemp: latestSnapshot.coolantTempCelsius = tv
        case .controlModuleVoltage: latestSnapshot.controlModuleVoltage = tv
        case .engineLoad: latestSnapshot.engineLoadPercent = tv
        case .throttlePosition: latestSnapshot.throttlePositionPercent = tv
        case .intakeAirTemp: latestSnapshot.intakeAirTempCelsius = tv
        case .mafAirFlow: latestSnapshot.mafGramsPerSec = tv
        case .fuelTankLevel: latestSnapshot.fuelTankLevelPercent = tv
        case .engineFuelRate: latestSnapshot.engineFuelRateLitersPerHour = tv
        case .ambientAirTemp: latestSnapshot.ambientAirTempCelsius = tv
        case .engineRuntime: latestSnapshot.engineRuntimeSeconds = tv
        case .shortFuelTrim1: latestSnapshot.shortTermFuelTrimPercent = tv
        case .longFuelTrim1: latestSnapshot.longTermFuelTrimPercent = tv
        case .timingAdvance: latestSnapshot.timingAdvanceDegrees = tv
        case .oxygenSensor1: latestSnapshot.oxygenSensor1VoltageVolts = tv
        case .monitorStatus: break
        }
        latestSnapshot.timestamp = Date()
        onSnapshotUpdate?(latestSnapshot)
    }
}
