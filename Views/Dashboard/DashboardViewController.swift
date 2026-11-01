import UIKit

/// Main cockpit screen: header, center speedometer/tachometer, parameter
/// grid, and footer trip summary. Phase 1 wires this to `OBDSimulator` via
/// `DashboardViewModel`; later phases swap the view model's data source to
/// a real `OBDEngine` without touching this view controller.
final class DashboardViewController: UIViewController {
    private let viewModel = DashboardViewModel()

    private let headerView = DashboardHeaderView()
    private let footerView = DashboardFooterView()

    private let speedometer = GaugeView()
    private let tachometer = GaugeView()

    private let coolantTile = ParameterTileView(title: "Coolant Temp")
    private let voltageTile = ParameterTileView(title: "Battery Voltage")
    private let fuelConsumptionTile = ParameterTileView(title: "Fuel Consumption")
    private let avgFuelConsumptionTile = ParameterTileView(title: "Avg Consumption")
    private let engineLoadTile = ParameterTileView(title: "Engine Load")
    private let throttleTile = ParameterTileView(title: "Throttle Position")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        configureGauges()
        configureThresholds()
        layoutUI()
        bindViewModel()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.stop()
    }

    private func configureGauges() {
        speedometer.title = "Speed"
        speedometer.unit = "km/h"
        speedometer.minValue = 0
        speedometer.maxValue = 200
        speedometer.majorTickCount = 10

        tachometer.title = "RPM"
        tachometer.unit = "x1000/min"
        tachometer.minValue = 0
        tachometer.maxValue = 7000
        tachometer.majorTickCount = 7
        tachometer.dangerThreshold = 6000
        tachometer.valueFormatter = { String(format: "%.1f", $0 / 1000.0) }
    }

    private func configureThresholds() {
        let settings = SettingsStore.shared.settings.value
        coolantTile.dangerThreshold = settings.coolantWarningCelsius
        voltageTile.dangerThreshold = settings.voltageWarningHigh
        voltageTile.warningThreshold = nil
    }

    private func layoutUI() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        footerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        view.addSubview(footerView)

        let gaugesRow = UIStackView(arrangedSubviews: [speedometer, tachometer])
        gaugesRow.axis = .horizontal
        gaugesRow.distribution = .fillEqually
        gaugesRow.spacing = 16

        let paramColumnLeft = UIStackView(arrangedSubviews: [coolantTile, voltageTile, fuelConsumptionTile])
        let paramColumnRight = UIStackView(arrangedSubviews: [avgFuelConsumptionTile, engineLoadTile, throttleTile])
        for column in [paramColumnLeft, paramColumnRight] {
            column.axis = .vertical
            column.spacing = 10
            column.distribution = .fillEqually
        }
        let paramGrid = UIStackView(arrangedSubviews: [paramColumnLeft, paramColumnRight])
        paramGrid.axis = .horizontal
        paramGrid.spacing = 10
        paramGrid.distribution = .fillEqually

        let contentRow = UIStackView(arrangedSubviews: [gaugesRow, paramGrid])
        contentRow.axis = .horizontal
        contentRow.spacing = 20
        contentRow.distribution = .fill
        paramGrid.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        gaugesRow.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        contentRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentRow)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentRow.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16),
            contentRow.bottomAnchor.constraint(equalTo: footerView.topAnchor, constant: -16),
            contentRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            paramGrid.widthAnchor.constraint(equalTo: contentRow.widthAnchor, multiplier: 0.34)
        ])
    }

    private func bindViewModel() {
        viewModel.vehicleName.observe { [weak self] name in
            self?.headerView.update(vehicleName: name, clockText: self?.viewModel.clockText.value ?? "")
        }
        viewModel.clockText.observe { [weak self] clock in
            self?.headerView.update(vehicleName: self?.viewModel.vehicleName.value ?? "", clockText: clock)
        }

        viewModel.connectionState.observe { [weak self] state in
            self?.headerView.bluetoothStatusPill.update(for: state)
            self?.headerView.ecuStatusPill.update(for: state)
            self?.footerView.connectionStatusPill.update(for: state)
        }

        viewModel.snapshot.observe { [weak self] snapshot in
            self?.render(snapshot)
        }

        viewModel.tripDistanceKm.observe { [weak self] _ in
            self?.updateFooter()
        }
        viewModel.tripElapsedSeconds.observe { [weak self] _ in
            self?.updateFooter()
        }
        viewModel.tripFuelUsedLiters.observe { [weak self] _ in
            self?.updateFooter()
        }
    }

    private func updateFooter() {
        footerView.update(distanceKm: viewModel.tripDistanceKm.value,
                           elapsedSeconds: viewModel.tripElapsedSeconds.value,
                           fuelUsedLiters: viewModel.tripFuelUsedLiters.value)
    }

    private func render(_ snapshot: TelemetrySnapshot) {
        if let speed = snapshot.vehicleSpeedKmh?.value {
            speedometer.setValue(speed)
        }
        if let rpm = snapshot.engineRpm?.value {
            tachometer.setValue(rpm)
        }
        if let coolant = snapshot.coolantTempCelsius {
            coolantTile.update(value: coolant.value, unit: "°C", source: coolant.source)
        }
        if let voltage = snapshot.controlModuleVoltage {
            voltageTile.update(value: voltage.value, unit: "V", source: voltage.source, decimals: 1)
        }
        if let load = snapshot.engineLoadPercent {
            engineLoadTile.update(value: load.value, unit: "%", source: load.source)
        }
        if let throttle = snapshot.throttlePositionPercent {
            throttleTile.update(value: throttle.value, unit: "%", source: throttle.source)
        }

        updateFuelConsumptionTiles(with: snapshot)
    }

    /// Lightweight inline preview of the instantaneous/average fuel
    /// consumption display rules (L/h near zero speed, else L/100km). The
    /// full Fuel Consumption Engine with ECU-vs-MAF source selection and
    /// since-reset averaging lands in Phase 4 — this keeps Phase 1 honest
    /// about being simulator-sourced in the meantime.
    private func updateFuelConsumptionTiles(with snapshot: TelemetrySnapshot) {
        guard let fuelRate = snapshot.engineFuelRateLitersPerHour,
              let speed = snapshot.vehicleSpeedKmh?.value else {
            fuelConsumptionTile.update(text: "--", source: nil)
            return
        }

        if speed < 3 {
            fuelConsumptionTile.update(value: fuelRate.value, unit: "L/h", source: fuelRate.source, decimals: 1)
        } else {
            let litersPer100km = fuelRate.value * 100.0 / speed
            fuelConsumptionTile.update(value: litersPer100km, unit: "L/100km", source: fuelRate.source, decimals: 1)
        }

        let distance = viewModel.tripDistanceKm.value
        let fuelUsed = viewModel.tripFuelUsedLiters.value
        if distance > 0.05 {
            avgFuelConsumptionTile.update(value: fuelUsed * 100.0 / distance, unit: "L/100km", source: .simulated, decimals: 1)
        } else {
            avgFuelConsumptionTile.update(text: "--", source: nil)
        }
    }
}
