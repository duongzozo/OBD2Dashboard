import UIKit

/// Persistent, unmissable banner shown whenever telemetry is coming from
/// the simulator rather than a real OBD-II adapter. Per spec, demo data
/// must never be presented ambiguously alongside real data.
final class DemoModeBadge: UIView {
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = Theme.warning
        layer.cornerRadius = 6

        label.text = "● DEMO MODE — SIMULATED DATA"
        label.font = Theme.labelFont(size: 12, weight: .bold)
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
}
