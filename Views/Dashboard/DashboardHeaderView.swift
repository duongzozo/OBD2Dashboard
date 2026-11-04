import UIKit

/// Dashboard header: logo, Bluetooth status, ECU status, vehicle name, clock.
final class DashboardHeaderView: UIView {
    private let logoLabel = UILabel()
    private let vehicleNameLabel = UILabel()
    let bluetoothStatusPill = StatusPillView()
    let ecuStatusPill = StatusPillView()
    private let clockLabel = UILabel()

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = Theme.surface

        logoLabel.text = "OBD-II  DASHBOARD PRO"
        logoLabel.font = Theme.labelFont(size: 15, weight: .bold)
        logoLabel.textColor = Theme.accent

        vehicleNameLabel.font = Theme.labelFont(size: 13, weight: .regular)
        vehicleNameLabel.textColor = Theme.textSecondary

        clockLabel.font = Theme.digitFont(size: 18, weight: .semibold)
        clockLabel.textColor = Theme.textPrimary

        let leftStack = UIStackView(arrangedSubviews: [logoLabel, vehicleNameLabel])
        leftStack.axis = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 2

        let statusStack = UIStackView(arrangedSubviews: [bluetoothStatusPill, ecuStatusPill, clockLabel])
        statusStack.axis = .horizontal
        statusStack.alignment = .center
        statusStack.spacing = 10

        let row = UIStackView(arrangedSubviews: [leftStack, UIView(), statusStack])
        row.axis = .horizontal
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let hairline = UIView()
        hairline.backgroundColor = Theme.hairline
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    func update(vehicleName: String, clockText: String) {
        vehicleNameLabel.text = vehicleName
        clockLabel.text = clockText
    }
}
