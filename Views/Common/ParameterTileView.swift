import UIKit

/// A small reusable parameter card for the dashboard's parameter grid
/// (coolant, voltage, fuel consumption, engine load, etc). Shows a label,
/// a large value, a unit, and a data-source badge so simulated/estimated
/// values are never confused with real ECU readings.
final class ParameterTileView: UIView {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let unitLabel = UILabel()
    private let sourceBadge = UILabel()

    var dangerThreshold: Double?
    var warningThreshold: Double?

    init(title: String) {
        super.init(frame: .zero)
        setup()
        titleLabel.text = title.uppercased()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = Theme.surface
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = Theme.hairline.cgColor

        titleLabel.font = Theme.labelFont(size: 12, weight: .semibold)
        titleLabel.textColor = Theme.textTertiary

        valueLabel.font = Theme.digitFont(size: 26)
        valueLabel.textColor = Theme.textPrimary
        valueLabel.text = "--"

        unitLabel.font = Theme.labelFont(size: 12)
        unitLabel.textColor = Theme.textSecondary

        sourceBadge.font = Theme.labelFont(size: 9, weight: .bold)
        sourceBadge.textColor = Theme.textTertiary
        sourceBadge.textAlignment = .right

        let valueRow = UIStackView(arrangedSubviews: [valueLabel, unitLabel])
        valueRow.axis = .horizontal
        valueRow.alignment = .lastBaseline
        valueRow.spacing = 4

        let headerRow = UIStackView(arrangedSubviews: [titleLabel, sourceBadge])
        headerRow.axis = .horizontal
        headerRow.distribution = .equalSpacing

        let mainStack = UIStackView(arrangedSubviews: [headerRow, valueRow])
        mainStack.axis = .vertical
        mainStack.spacing = 6
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    func update(value: Double?, unit: String, source: DataSource?, decimals: Int = 0) {
        if let value = value {
            valueLabel.text = String(format: "%.\(decimals)f", value)
        } else {
            valueLabel.text = "--"
        }
        unitLabel.text = unit
        sourceBadge.text = source?.displayLabel

        if let value = value, let danger = dangerThreshold, value >= danger {
            valueLabel.textColor = Theme.danger
        } else if let value = value, let warn = warningThreshold, value >= warn {
            valueLabel.textColor = Theme.warning
        } else {
            valueLabel.textColor = Theme.textPrimary
        }
    }

    func update(text: String, source: DataSource? = nil) {
        valueLabel.text = text
        unitLabel.text = ""
        sourceBadge.text = source?.displayLabel
        valueLabel.textColor = Theme.textPrimary
    }
}
