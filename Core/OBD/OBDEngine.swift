import Foundation

/// The real-hardware counterpart to `Simulator/OBDSimulator.swift`. Same
/// priority-grouped fast/slow polling pattern already proven there
/// (speed/RPM/throttle fast; coolant/voltage/fuel/etc. slow) and the same
/// `TelemetrySnapshot` output — but every value here comes from an actual
/// ECU round-trip over `OBDRequestQueue`, tagged `.ecuReported`, and only
/// for PIDs `ELM327Initializer` confirmed this ECU supports.
final class OBDEngine {
    let ecuState: Observable<ConnectionState> = Observable(.disconnected)
    var onSnapshotUpdate: ((TelemetrySnapshot) -> Void)?

    private let bluetoothManager: BluetoothManager
    private let queue: OBDRequestQueue
    private let initializer: ELM327Initializer
    private var supportedPIDs: Set<OBDPID> = []
    private var fastTimer: Timer?
    private var slowTimer: Timer?
    private var latestSnapshot = TelemetrySnapshot.empty

    private static let fastPIDs: [OBDPID] = [.vehicleSpeed, .engineRPM, .throttlePosition]
    private static let slowPIDs: [OBDPID] = [
        .coolantTemp, .controlModuleVoltage, .fuelTankLevel, .engineFuelRate,
        .mafAirFlow, .ambientAirTemp, .intakeAirTemp, .engineRuntime,
        .shortFuelTrim1, .longFuelTrim1, .timingAdvance, .engineLoad, .oxygenSensor1
    ]

    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
        self.queue = OBDRequestQueue(transport: bluetoothManager.transport)
        self.initializer = ELM327Initializer(queue: queue)

        bluetoothManager.connectionState.observe { [weak self] state in
            switch state {
            case .connected:
                self?.beginInitialization()
            case .disconnected, .error:
                self?.stop()
                self?.ecuState.value = .disconnected
            default:
                break
            }
        }
    }

    func stop() {
        fastTimer?.invalidate()
        fastTimer = nil
        slowTimer?.invalidate()
        slowTimer = nil
    }

    private func beginInitialization() {
        ecuState.value = .initializing
        initializer.initialize { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let supported):
                    self?.supportedPIDs = supported
                    self?.ecuState.value = .ecuReady
                    self?.startPolling()
                case .failure(let error):
                    self?.ecuState.value = .error("ELM327 init failed: \(error)")
                }
            }
        }
    }

    private func startPolling() {
        let settings = SettingsStore.shared.settings.value
        let fastInterval = max(0.1, Double(settings.dashboardPollingIntervalMs) / 1000.0)

        fastTimer = Timer.scheduledTimer(withTimeInterval: fastInterval, repeats: true) { [weak self] _ in
            self?.pollFast()
        }
        slowTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollSlow()
        }
    }

    private func pollFast() {
        for pid in Self.fastPIDs where supportedPIDs.contains(pid) {
            poll(pid)
        }
    }

    private func pollSlow() {
        for pid in Self.slowPIDs where supportedPIDs.contains(pid) {
            poll(pid)
        }
    }

    private func poll(_ pid: OBDPID) {
        let timeoutMs = SettingsStore.shared.settings.value.obdRequestTimeoutMs
        queue.enqueue("01" + pid.hexString, timeoutMs: timeoutMs) { [weak self] result in
            guard let self = self, case .success(let response) = result else { return }
            guard let dataBytes = try? OBDResponseParser.mode01DataBytes(fromResponse: response, expectedPID: pid),
                  let value = PIDDecoder.decode(pid: pid, bytes: dataBytes) else { return }
            DispatchQueue.main.async {
                self.apply(pid: pid, value: value)
            }
        }
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
