import UIKit

/// Small rounded status indicator used for Bluetooth/ECU connection state
/// in the dashboard header and footer.
final class StatusPillView: UIView {
    private let dot = UIView()
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
        backgroundColor = Theme.surfaceElevated
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = Theme.hairline.cgColor

        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false

        label.font = Theme.labelFont(size: 12, weight: .semibold)
        label.textColor = Theme.textPrimary

        let stack = UIStackView(arrangedSubviews: [dot, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    func update(text: String, color: UIColor) {
        label.text = text
        dot.backgroundColor = color
    }

    func update(for state: ConnectionState) {
        switch state {
        case .disconnected: update(text: state.shortLabel, color: Theme.textTertiary)
        case .scanning, .connecting, .initializing: update(text: state.shortLabel, color: Theme.warning)
        case .connected, .ecuReady: update(text: state.shortLabel, color: Theme.success)
        case .error: update(text: state.shortLabel, color: Theme.danger)
        }
    }
}
