import UIKit

/// Functional in Phase 1: vehicle profile fields, units, warning thresholds,
/// night mode, power-save mode, and the demo-mode toggle, all persisted via
/// `SettingsStore`. Adapter/BLE UUID fields (spec section 10) are deferred
/// to Phase 2 since there's no Bluetooth transport yet to configure.
final class SettingsViewController: UIViewController {
    private let store = SettingsStore.shared
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let vehicleNameField = SettingsViewController.makeTextField()
    private let displacementField = SettingsViewController.makeTextField(keyboard: .decimalPad)
    private let fuelTypeSegment = UISegmentedControl(items: VehicleProfile.FuelType.allCases.map { $0.displayName })
    private let speedUnitSegment = UISegmentedControl(items: SpeedUnit.allCases.map { $0.symbol })
    private let temperatureUnitSegment = UISegmentedControl(items: TemperatureUnit.allCases.map { $0.symbol })
    private let nightModeSwitch = UISwitch()
    private let powerSaveSwitch = UISwitch()
    private let demoModeSwitch = UISwitch()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Settings"
        buildLayout()
        loadFromStore()
    }

    private static func makeTextField(keyboard: UIKeyboardType = .default) -> UITextField {
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.keyboardType = keyboard
        field.textColor = Theme.textPrimary
        field.backgroundColor = Theme.surfaceElevated
        return field
    }

    private func section(title: String, rows: [UIView]) -> UIView {
        let header = UILabel()
        header.text = title.uppercased()
        header.font = Theme.labelFont(size: 13, weight: .bold)
        header.textColor = Theme.accent

        let card = UIStackView(arrangedSubviews: rows)
        card.axis = .vertical
        card.spacing = 12
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        card.backgroundColor = Theme.surface
        card.layer.cornerRadius = 12

        let wrapper = UIStackView(arrangedSubviews: [header, card])
        wrapper.axis = .vertical
        wrapper.spacing = 8
        return wrapper
    }

    private func labeledRow(_ label: String, _ control: UIView) -> UIView {
        let labelView = UILabel()
        labelView.text = label
        labelView.font = Theme.labelFont(size: 14)
        labelView.textColor = Theme.textSecondary
        labelView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [labelView, control])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        return row
    }

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 40),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -40),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -80)
        ])

        for segment in [fuelTypeSegment, speedUnitSegment, temperatureUnitSegment] {
            segment.addTarget(self, action: #selector(valuesChanged), for: .valueChanged)
        }
        for toggle in [nightModeSwitch, powerSaveSwitch, demoModeSwitch] {
            toggle.addTarget(self, action: #selector(valuesChanged), for: .valueChanged)
        }
        vehicleNameField.addTarget(self, action: #selector(valuesChanged), for: .editingDidEnd)
        displacementField.addTarget(self, action: #selector(valuesChanged), for: .editingDidEnd)

        contentStack.addArrangedSubview(section(title: "Vehicle Profile", rows: [
            labeledRow("Vehicle Name", vehicleNameField),
            labeledRow("Engine Displacement (L)", displacementField),
            labeledRow("Fuel Type", fuelTypeSegment)
        ]))

        contentStack.addArrangedSubview(section(title: "Units", rows: [
            labeledRow("Speed Unit", speedUnitSegment),
            labeledRow("Temperature Unit", temperatureUnitSegment)
        ]))

        contentStack.addArrangedSubview(section(title: "Display", rows: [
            labeledRow("Night Mode", nightModeSwitch),
            labeledRow("Power Save Mode", powerSaveSwitch)
        ]))

        contentStack.addArrangedSubview(section(title: "Data Source", rows: [
            labeledRow("Demo Mode (Simulator)", demoModeSwitch)
        ]))
    }

    private func loadFromStore() {
        let settings = store.settings.value
        vehicleNameField.text = settings.vehicleProfile.name
        displacementField.text = String(settings.vehicleProfile.engineDisplacementLiters)
        if let index = VehicleProfile.FuelType.allCases.firstIndex(of: settings.vehicleProfile.fuelType) {
            fuelTypeSegment.selectedSegmentIndex = index
        }
        if let index = SpeedUnit.allCases.firstIndex(of: settings.speedUnit) {
            speedUnitSegment.selectedSegmentIndex = index
        }
        if let index = TemperatureUnit.allCases.firstIndex(of: settings.temperatureUnit) {
            temperatureUnitSegment.selectedSegmentIndex = index
        }
        nightModeSwitch.isOn = settings.nightModeEnabled
        powerSaveSwitch.isOn = settings.powerSaveModeEnabled
        demoModeSwitch.isOn = settings.demoModeEnabled
    }

    @objc private func valuesChanged() {
        store.update { settings in
            settings.vehicleProfile.name = vehicleNameField.text?.isEmpty == false
                ? vehicleNameField.text! : settings.vehicleProfile.name
            if let displacement = Double(displacementField.text ?? "") {
                settings.vehicleProfile.engineDisplacementLiters = displacement
            }
            let fuelType = VehicleProfile.FuelType.allCases[fuelTypeSegment.selectedSegmentIndex]
            if fuelType != settings.vehicleProfile.fuelType {
                settings.vehicleProfile.fuelType = fuelType
                settings.vehicleProfile.airFuelRatio = fuelType.defaultAirFuelRatio
                settings.vehicleProfile.fuelDensityGramsPerLiter = fuelType.defaultFuelDensityGramsPerLiter
            }
            settings.speedUnit = SpeedUnit.allCases[speedUnitSegment.selectedSegmentIndex]
            settings.temperatureUnit = TemperatureUnit.allCases[temperatureUnitSegment.selectedSegmentIndex]
            settings.nightModeEnabled = nightModeSwitch.isOn
            settings.powerSaveModeEnabled = powerSaveSwitch.isOn
            settings.demoModeEnabled = demoModeSwitch.isOn
        }
        Theme.isNightMode = nightModeSwitch.isOn
    }
}
