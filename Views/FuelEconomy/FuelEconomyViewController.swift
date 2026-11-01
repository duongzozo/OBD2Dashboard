import UIKit

/// Real Phase 4 fuel economy screen: instantaneous consumption (with
/// source badge), current-trip average, and since-reset average — each
/// clearly labeled so ECU/calculated/estimated/demo values are never
/// confused (spec §6).
final class FuelEconomyViewController: UIViewController {
    private let hub = TelemetryHub.shared

    private let instantTile = ParameterTileView(title: "Instantaneous")
    private let currentTripTile = ParameterTileView(title: "Current Trip Avg")
    private let sinceResetTile = ParameterTileView(title: "Since Reset Avg")
    private let demoBadge = DemoModeBadge()
    private let resetButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Fuel Economy"
        buildLayout()
        bind()
    }

    private func buildLayout() {
        resetButton.setTitle("Reset Since-Last Fill-Up", for: .normal)
        resetButton.setTitleColor(Theme.background, for: .normal)
        resetButton.backgroundColor = Theme.accent
        resetButton.layer.cornerRadius = 8
        resetButton.titleLabel?.font = Theme.labelFont(size: 14, weight: .bold)
        resetButton.addTarget(self, action: #selector(resetSinceResetTapped), for: .touchUpInside)

        let tilesRow = UIStackView(arrangedSubviews: [instantTile, currentTripTile, sinceResetTile])
        tilesRow.axis = .horizontal
        tilesRow.spacing = 16
        tilesRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [demoBadge, tilesRow, resetButton])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            resetButton.heightAnchor.constraint(equalToConstant: 44),
            resetButton.widthAnchor.constraint(equalToConstant: 260)
        ])
    }

    private func bind() {
        hub.snapshot.observe { [weak self] snapshot in
            self?.render(snapshot)
        }
        hub.bluetoothState.observe { [weak self] state in
            self?.demoBadge.isHidden = state != .demoMode
        }
        hub.tripComputer.currentTrip.observe { [weak self] trip in
            self?.updateAverage(tile: self?.currentTripTile, trip: trip)
        }
        hub.tripComputer.sinceReset.observe { [weak self] trip in
            self?.updateAverage(tile: self?.sinceResetTile, trip: trip)
        }
    }

    private func render(_ snapshot: TelemetrySnapshot) {
        let profile = SettingsStore.shared.settings.value.vehicleProfile
        guard let result = FuelConsumptionEngine.compute(snapshot: snapshot, profile: profile) else {
            instantTile.update(text: "--", source: nil)
            return
        }
        instantTile.update(value: result.value, unit: result.isPer100km ? "L/100km" : "L/h",
                            source: result.source, decimals: 1)
    }

    private func updateAverage(tile: ParameterTileView?, trip: TripRecord) {
        guard let tile = tile else { return }
        if let average = trip.averageConsumptionPer100km {
            tile.update(value: average, unit: "L/100km", source: .calculated, decimals: 1)
        } else {
            tile.update(text: "--", source: nil)
        }
    }

    @objc private func resetSinceResetTapped() {
        hub.tripComputer.resetSinceReset()
    }
}
