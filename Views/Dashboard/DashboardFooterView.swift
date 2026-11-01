import UIKit

/// Dashboard footer: trip distance, trip time, fuel used, connection status.
final class DashboardFooterView: UIView {
    private let distanceLabel = UILabel()
    private let timeLabel = UILabel()
    private let fuelUsedLabel = UILabel()
    let connectionStatusPill = StatusPillView()

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func makeMetric(title: String, valueLabel: UILabel) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title.uppercased()
        titleLabel.font = Theme.labelFont(size: 10, weight: .semibold)
        titleLabel.textColor = Theme.textTertiary

        valueLabel.font = Theme.digitFont(size: 16, weight: .semibold)
        valueLabel.textColor = Theme.textPrimary

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 2
        return stack
    }

    private func setup() {
        backgroundColor = Theme.surface

        let hairline = UIView()
        hairline.backgroundColor = Theme.hairline
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        let metricsRow = UIStackView(arrangedSubviews: [
            makeMetric(title: "Trip Distance", valueLabel: distanceLabel),
            makeMetric(title: "Trip Time", valueLabel: timeLabel),
            makeMetric(title: "Fuel Used", valueLabel: fuelUsedLabel)
        ])
        metricsRow.axis = .horizontal
        metricsRow.spacing = 28

        let row = UIStackView(arrangedSubviews: [metricsRow, UIView(), connectionStatusPill])
        row.axis = .horizontal
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])

        update(distanceKm: 0, elapsedSeconds: 0, fuelUsedLiters: 0)
    }

    func update(distanceKm: Double, elapsedSeconds: Double, fuelUsedLiters: Double) {
        distanceLabel.text = String(format: "%.1f km", distanceKm)
        let minutes = Int(elapsedSeconds) / 60
        let seconds = Int(elapsedSeconds) % 60
        timeLabel.text = String(format: "%02d:%02d", minutes, seconds)
        fuelUsedLabel.text = String(format: "%.2f L", fuelUsedLiters)
    }
}
