import UIKit

/// Main cockpit screen: header, center speedometer/tachometer, parameter
/// grid, and footer trip summary, all fed by `OBDEngine` through
/// `DashboardViewModel`.
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

    private static let speedometerMaxKmh = 200.0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        configureGauges()
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
        speedometer.minValue = 0
        speedometer.majorTickCount = 10

        tachometer.title = "RPM"
        tachometer.unit = "x1000/min"
        tachometer.minValue = 0
        tachometer.maxValue = 7000
        tachometer.majorTickCount = 7
        tachometer.dangerThreshold = 6000
        tachometer.valueFormatter = { String(format: "%.1f", $0 / 1000.0) }
    }

    /// Units and warning limits come from Settings and can change at any time.
    private func applySettings(_ settings: AppSettings) {
        speedometer.unit = settings.speedUnit.symbol
        speedometer.maxValue = settings.speedUnit.convert(fromKmh: Self.speedometerMaxKmh)
        speedometer.dangerThreshold = settings.speedUnit.convert(fromKmh: settings.speedWarningKmh)
        coolantTile.dangerThreshold = settings.temperatureUnit.convert(fromCelsius: settings.coolantWarningCelsius)
        voltageTile.dangerThreshold = settings.voltageWarningHigh
        voltageTile.lowDangerThreshold = settings.voltageWarningLow
        render(viewModel.snapshot.value)
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

        viewModel.bluetoothState.observe { [weak self] state in
            self?.headerView.bluetoothStatusPill.update(for: state)
            self?.footerView.connectionStatusPill.update(for: state)
        }
        viewModel.ecuState.observe { [weak self] state in
            self?.headerView.ecuStatusPill.update(for: state)
        }

        SettingsStore.shared.settings.observe { [weak self] settings in
            self?.applySettings(settings)
        }

        viewModel.snapshot.observe { [weak self] snapshot in
            self?.render(snapshot)
        }

        viewModel.tripComputer.currentTrip.observe { [weak self] trip in
            self?.footerView.update(distanceKm: trip.distanceKm,
                                     elapsedSeconds: trip.elapsedSeconds,
                                     fuelUsedLiters: trip.fuelUsedLiters)
        }
    }

    private func render(_ snapshot: TelemetrySnapshot) {
        let settings = SettingsStore.shared.settings.value

        if let speed = snapshot.vehicleSpeedKmh?.value {
            speedometer.setValue(settings.speedUnit.convert(fromKmh: speed))
        } else {
            speedometer.clearValue()
        }
        if let rpm = snapshot.engineRpm?.value {
            tachometer.setValue(rpm)
        } else {
            tachometer.clearValue()
        }

        let coolant = snapshot.coolantTempCelsius
        coolantTile.update(value: coolant.map { settings.temperatureUnit.convert(fromCelsius: $0.value) },
                           unit: settings.temperatureUnit.symbol, source: coolant?.source)
        voltageTile.update(value: snapshot.controlModuleVoltage?.value, unit: "V",
                           source: snapshot.controlModuleVoltage?.source, decimals: 1)
        engineLoadTile.update(value: snapshot.engineLoadPercent?.value, unit: "%",
                              source: snapshot.engineLoadPercent?.source)
        throttleTile.update(value: snapshot.throttlePositionPercent?.value, unit: "%",
                            source: snapshot.throttlePositionPercent?.source)

        updateFuelConsumptionTiles(with: snapshot, profile: settings.vehicleProfile)
    }

    private func updateFuelConsumptionTiles(with snapshot: TelemetrySnapshot, profile: VehicleProfile) {
        if let result = FuelConsumptionEngine.compute(snapshot: snapshot, profile: profile) {
            fuelConsumptionTile.update(value: result.value, unit: result.isPer100km ? "L/100km" : "L/h",
                                       source: result.source, decimals: 1)
        } else {
            fuelConsumptionTile.update(text: "--", source: nil)
        }

        // The average is an accumulated figure, still valid with no live reading.
        if let average = viewModel.tripComputer.sinceReset.value.averageConsumptionPer100km {
            avgFuelConsumptionTile.update(value: average, unit: "L/100km", source: .calculated, decimals: 1)
        } else {
            avgFuelConsumptionTile.update(text: "--", source: nil)
        }
    }
}
