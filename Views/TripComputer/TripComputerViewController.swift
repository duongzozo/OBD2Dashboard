import UIKit

/// Real Phase 4 trip computer: current trip (distance/time/fuel/avg) and
/// since-reset totals, each individually resettable (spec §6: "Current
/// trip average... Since reset average... Reset trip").
final class TripComputerViewController: UIViewController {
    private let hub = TelemetryHub.shared

    private let currentDistanceTile = ParameterTileView(title: "Trip Distance")
    private let currentTimeTile = ParameterTileView(title: "Trip Time")
    private let currentFuelTile = ParameterTileView(title: "Fuel Used")
    private let currentAvgTile = ParameterTileView(title: "Trip Avg")

    private let resetDistanceTile = ParameterTileView(title: "Since Reset Distance")
    private let resetTimeTile = ParameterTileView(title: "Since Reset Time")
    private let resetFuelTile = ParameterTileView(title: "Since Reset Fuel")
    private let resetAvgTile = ParameterTileView(title: "Since Reset Avg")

    private let resetCurrentButton = UIButton(type: .system)
    private let resetSinceResetButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Trip Computer"
        buildLayout()
        bind()
    }

    private func makeRow(_ tiles: [ParameterTileView]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: tiles)
        row.axis = .horizontal
        row.spacing = 16
        row.distribution = .fillEqually
        return row
    }

    private func buildLayout() {
        resetCurrentButton.setTitle("Reset Current Trip", for: .normal)
        resetSinceResetButton.setTitle("Reset Since-Reset Totals", for: .normal)
        for button in [resetCurrentButton, resetSinceResetButton] {
            button.setTitleColor(Theme.background, for: .normal)
            button.backgroundColor = Theme.accent
            button.layer.cornerRadius = 8
            button.titleLabel?.font = Theme.labelFont(size: 14, weight: .bold)
        }
        resetCurrentButton.addTarget(self, action: #selector(resetCurrentTapped), for: .touchUpInside)
        resetSinceResetButton.addTarget(self, action: #selector(resetSinceResetTapped), for: .touchUpInside)

        let buttonsRow = UIStackView(arrangedSubviews: [resetCurrentButton, resetSinceResetButton])
        buttonsRow.axis = .horizontal
        buttonsRow.spacing = 16
        buttonsRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [
            makeRow([currentDistanceTile, currentTimeTile, currentFuelTile, currentAvgTile]),
            makeRow([resetDistanceTile, resetTimeTile, resetFuelTile, resetAvgTile]),
            buttonsRow
        ])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            buttonsRow.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func bind() {
        hub.tripComputer.currentTrip.observe { [weak self] trip in
            self?.update(distance: self?.currentDistanceTile, time: self?.currentTimeTile,
                         fuel: self?.currentFuelTile, avg: self?.currentAvgTile, trip: trip)
        }
        hub.tripComputer.sinceReset.observe { [weak self] trip in
            self?.update(distance: self?.resetDistanceTile, time: self?.resetTimeTile,
                         fuel: self?.resetFuelTile, avg: self?.resetAvgTile, trip: trip)
        }
    }

    private func update(distance: ParameterTileView?, time: ParameterTileView?,
                         fuel: ParameterTileView?, avg: ParameterTileView?, trip: TripRecord) {
        distance?.update(value: trip.distanceKm, unit: "km", source: nil, decimals: 1)
        let minutes = Int(trip.elapsedSeconds) / 60
        let seconds = Int(trip.elapsedSeconds) % 60
        time?.update(text: String(format: "%02d:%02d", minutes, seconds))
        fuel?.update(value: trip.fuelUsedLiters, unit: "L", source: nil, decimals: 2)
        if let average = trip.averageConsumptionPer100km {
            avg?.update(value: average, unit: "L/100km", source: .calculated, decimals: 1)
        } else {
            avg?.update(text: "--")
        }
    }

    @objc private func resetCurrentTapped() {
        hub.tripComputer.resetCurrentTrip()
    }

    @objc private func resetSinceResetTapped() {
        hub.tripComputer.resetSinceReset()
    }
}
