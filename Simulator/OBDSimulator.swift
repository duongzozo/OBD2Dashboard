import Foundation

/// Phase 1 DEMO MODE telemetry generator. Produces a plausible driving
/// cycle (idle → accelerate → cruise → decelerate → stop, repeating) so the
/// dashboard, gauges, charts, and warning thresholds can all be exercised
/// before any real ELM327 adapter is connected.
///
/// Mirrors the priority-polling architecture the real OBDEngine will use:
/// high-priority fields (speed/RPM/throttle) tick fast, low-priority fields
/// (coolant/voltage/fuel level/etc.) tick slow — so swapping this out for a
/// real Bluetooth-backed engine later doesn't change how the ViewModel
/// consumes snapshots.
///
/// Every value this emits is tagged `.simulated` via `DataSource` — it must
/// never be presented as real ECU data.
final class OBDSimulator {
    struct Config {
        var fastIntervalMs: Int = 150
        var slowIntervalMs: Int = 1000
    }

    private enum DrivingPhase: CaseIterable {
        case idle, accelerate, cruise, decelerate, stopped
    }

    /// Continuous simulated physical state, independent of the snapshot
    /// representation so phase transitions can reason about raw doubles.
    private struct SimState {
        var speedKmh: Double = 0
        var rpm: Double = 820
        var throttlePercent: Double = 0
        var coolantTempC: Double = 22
        var voltage: Double = 12.5
        var fuelLevelPercent: Double = 62
        var ambientTempC: Double = 24
        var runtimeSeconds: Double = 0
        var phase: DrivingPhase = .idle
        var phaseElapsed: Double = 0
    }

    private let config: Config
    private let queue = DispatchQueue(label: "com.diy.obd2dashboard.simulator", qos: .utility)
    private var fastTimer: DispatchSourceTimer?
    private var slowTimer: DispatchSourceTimer?
    private var state = SimState()
    private var latestSnapshot = TelemetrySnapshot.empty

    /// Always delivered on the main queue, matching how a real decoded OBD
    /// response would be handed off after background Bluetooth I/O.
    var onSnapshotUpdate: ((TelemetrySnapshot) -> Void)?

    init(config: Config = Config()) {
        self.config = config
    }

    func start() {
        stop()
        let fast = DispatchSource.makeTimerSource(queue: queue)
        fast.schedule(deadline: .now(), repeating: .milliseconds(config.fastIntervalMs))
        fast.setEventHandler { [weak self] in self?.tickFast() }
        fast.resume()
        fastTimer = fast

        let slow = DispatchSource.makeTimerSource(queue: queue)
        slow.schedule(deadline: .now(), repeating: .milliseconds(config.slowIntervalMs))
        slow.setEventHandler { [weak self] in self?.tickSlow() }
        slow.resume()
        slowTimer = slow
    }

    func stop() {
        fastTimer?.cancel()
        slowTimer?.cancel()
        fastTimer = nil
        slowTimer = nil
    }

    // MARK: - Fast tick (speed, RPM, throttle, engine load)

    private func tickFast() {
        advanceDrivingCycle(dt: Double(config.fastIntervalMs) / 1000.0)

        let now = Date()
        latestSnapshot.timestamp = now
        latestSnapshot.vehicleSpeedKmh = .simulated(state.speedKmh, at: now)
        latestSnapshot.engineRpm = .simulated(state.rpm, at: now)
        latestSnapshot.throttlePositionPercent = .simulated(state.throttlePercent, at: now)
        latestSnapshot.engineLoadPercent = .simulated(estimatedEngineLoad(), at: now)

        deliver()
    }

    // MARK: - Slow tick (coolant, voltage, fuel, intake/ambient, runtime)

    private func tickSlow() {
        let dt = Double(config.slowIntervalMs) / 1000.0
        let engineRunning = state.phase != .idle || state.rpm > 400

        if engineRunning {
            state.runtimeSeconds += dt
            // Asymptotic warm-up toward ~92C operating temperature.
            let target = 92.0
            state.coolantTempC += (target - state.coolantTempC) * min(1, dt / 90.0)
            state.voltage = 14.2 + Double.random(in: -0.15...0.15) - (state.throttlePercent / 100.0) * 0.3
            // Fuel burns very slowly in the demo; purely illustrative.
            state.fuelLevelPercent = max(0, state.fuelLevelPercent - dt * 0.0006)
        } else {
            state.coolantTempC += (22.0 - state.coolantTempC) * min(1, dt / 600.0)
            state.voltage = 12.4 + Double.random(in: -0.1...0.1)
        }

        let now = Date()
        latestSnapshot.coolantTempCelsius = .simulated(state.coolantTempC, at: now)
        latestSnapshot.controlModuleVoltage = .simulated(state.voltage, at: now)
        latestSnapshot.fuelTankLevelPercent = .simulated(state.fuelLevelPercent, at: now)
        latestSnapshot.ambientAirTempCelsius = .simulated(state.ambientTempC, at: now)
        latestSnapshot.intakeAirTempCelsius = .simulated(state.ambientTempC + 8 + state.throttlePercent / 20, at: now)
        latestSnapshot.engineRuntimeSeconds = .simulated(state.runtimeSeconds, at: now)
        latestSnapshot.mafGramsPerSec = .simulated(estimatedMAF(), at: now)
        latestSnapshot.engineFuelRateLitersPerHour = .simulated(estimatedFuelRateLitersPerHour(), at: now)
        latestSnapshot.shortTermFuelTrimPercent = .simulated(Double.random(in: -3...3), at: now)
        latestSnapshot.longTermFuelTrimPercent = .simulated(Double.random(in: -5...5), at: now)
        latestSnapshot.timingAdvanceDegrees = .simulated(10 + state.throttlePercent / 10, at: now)

        deliver()
    }

    private func deliver() {
        let snapshot = latestSnapshot
        let callback = onSnapshotUpdate
        DispatchQueue.main.async {
            callback?(snapshot)
        }
    }

    // MARK: - Driving cycle state machine

    private func advanceDrivingCycle(dt: Double) {
        state.phaseElapsed += dt

        switch state.phase {
        case .idle:
            state.rpm = smoothed(state.rpm, target: 820, rate: 0.5, dt: dt)
            state.speedKmh = smoothed(state.speedKmh, target: 0, rate: 1.0, dt: dt)
            state.throttlePercent = smoothed(state.throttlePercent, target: 2, rate: 1.0, dt: dt)
            if state.phaseElapsed > 6 { transition(to: .accelerate) }

        case .accelerate:
            state.throttlePercent = smoothed(state.throttlePercent, target: 55, rate: 1.2, dt: dt)
            state.speedKmh = smoothed(state.speedKmh, target: 100, rate: 0.35, dt: dt)
            state.rpm = smoothed(state.rpm, target: 2600, rate: 0.6, dt: dt)
            if state.speedKmh > 85 { transition(to: .cruise) }

        case .cruise:
            state.throttlePercent = smoothed(state.throttlePercent, target: 18, rate: 0.8, dt: dt)
            state.speedKmh = smoothed(state.speedKmh, target: 92 + sin(state.phaseElapsed / 3) * 4, rate: 0.4, dt: dt)
            state.rpm = smoothed(state.rpm, target: 1900, rate: 0.5, dt: dt)
            if state.phaseElapsed > 20 { transition(to: .decelerate) }

        case .decelerate:
            state.throttlePercent = smoothed(state.throttlePercent, target: 0, rate: 1.5, dt: dt)
            state.speedKmh = smoothed(state.speedKmh, target: 0, rate: 0.5, dt: dt)
            state.rpm = smoothed(state.rpm, target: 900, rate: 0.8, dt: dt)
            if state.speedKmh < 3 { transition(to: .stopped) }

        case .stopped:
            state.rpm = smoothed(state.rpm, target: 780, rate: 0.5, dt: dt)
            state.speedKmh = 0
            state.throttlePercent = smoothed(state.throttlePercent, target: 0, rate: 1.0, dt: dt)
            if state.phaseElapsed > 4 { transition(to: .idle) }
        }
    }

    private func transition(to phase: DrivingPhase) {
        state.phase = phase
        state.phaseElapsed = 0
    }

    private func smoothed(_ current: Double, target: Double, rate: Double, dt: Double) -> Double {
        let alpha = min(1, rate * dt)
        return current + (target - current) * alpha
    }

    private func estimatedEngineLoad() -> Double {
        let rpmFactor = min(1, state.rpm / 5000)
        return min(100, max(0, state.throttlePercent * 0.6 + rpmFactor * 25))
    }

    private func estimatedMAF() -> Double {
        // Rough synthetic relationship: more RPM and load -> more air mass flow.
        let load = estimatedEngineLoad()
        return max(1.5, (state.rpm / 1000.0) * (0.8 + load / 60.0))
    }

    private func estimatedFuelRateLitersPerHour() -> Double {
        guard state.rpm > 400 else { return 0 }
        let load = estimatedEngineLoad()
        return 0.5 + (load / 100.0) * 6.5 + (state.rpm / 6000.0) * 2.0
    }
}
