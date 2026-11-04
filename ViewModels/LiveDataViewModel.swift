import Foundation

/// One row of the Live Data screen.
struct LiveDataRow: Equatable {
    var pid: OBDPID
    var isSupported: Bool
    var value: TelemetryValue?
    var minimum: Double?
    var maximum: Double?
    var history: [Double]
}

/// Samples the shared telemetry stream on a fixed tick, independent of how
/// often PIDs arrive, and keeps per-PID history and min/max for the Live Data
/// screen. App-wide so a recording survives the screen being rebuilt, which
/// happens when night mode is switched.
final class LiveDataViewModel {
    static let shared = LiveDataViewModel()

    /// Fires after each tick, on the main thread.
    let rows: Observable<[LiveDataRow]> = Observable([])
    let isRecording: Observable<Bool> = Observable(false)
    private(set) var lastLogFile: URL?

    static let historyLength = 120
    private static let tickInterval: TimeInterval = 0.5
    private static let ticksPerLogSample = 2

    private let hub: TelemetryHub
    private let logger: TelemetryCSVLogger
    private var timer: Timer?
    private var tickCount = 0
    private var history: [OBDPID: [Double]] = [:]
    private var minimums: [OBDPID: Double] = [:]
    private var maximums: [OBDPID: Double] = [:]

    init(hub: TelemetryHub = .shared, logDirectory: URL? = nil) {
        self.hub = hub
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.logger = TelemetryCSVLogger(directory: logDirectory ?? documents)
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func resetStatistics() {
        history = [:]
        minimums = [:]
        maximums = [:]
        tick()
    }

    /// Returns the error message if recording could not start.
    func toggleRecording() -> String? {
        if logger.isRecording {
            lastLogFile = logger.stop()
            isRecording.value = false
            return nil
        }
        do {
            try logger.start()
            lastLogFile = nil
            isRecording.value = true
            return nil
        } catch {
            return "Could not create the log file: \(error.localizedDescription)"
        }
    }

    var recordedSampleCount: Int { logger.sampleCount }

    private func tick() {
        tickCount += 1
        let snapshot = hub.snapshot.value

        for pid in PIDDisplay.measuredPIDs {
            guard let value = snapshot.value(for: pid)?.value else { continue }
            var values = history[pid] ?? []
            values.append(value)
            if values.count > Self.historyLength {
                values.removeFirst(values.count - Self.historyLength)
            }
            history[pid] = values
            minimums[pid] = min(minimums[pid] ?? value, value)
            maximums[pid] = max(maximums[pid] ?? value, value)
        }

        if logger.isRecording, tickCount % Self.ticksPerLogSample == 0 {
            logger.append(snapshot)
        }

        rows.value = makeRows(snapshot: snapshot, supported: hub.supportedPIDs.value)
    }

    private func makeRows(snapshot: TelemetrySnapshot, supported: Set<OBDPID>) -> [LiveDataRow] {
        let all = PIDDisplay.measuredPIDs.map { pid in
            LiveDataRow(pid: pid,
                        // Before the ECU has been asked, nothing is known to be unsupported.
                        isSupported: supported.isEmpty || supported.contains(pid),
                        value: snapshot.value(for: pid),
                        minimum: minimums[pid],
                        maximum: maximums[pid],
                        history: history[pid] ?? [])
        }
        return all.filter { $0.isSupported } + all.filter { !$0.isSupported }
    }
}
