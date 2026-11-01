import UIKit

/// Shared "coming in a later phase" screen so the full 7-tab navigation
/// shell exists and is navigable in Phase 1, even though Live Data, Fuel
/// Economy, Diagnostic, Trip Computer, and Vehicle Information aren't
/// implemented yet (those land in Phases 3–5 per the roadmap).
class PlaceholderViewController: UIViewController {
    private let screenTitle: String
    private let phaseNote: String

    init(screenTitle: String, phaseNote: String) {
        self.screenTitle = screenTitle
        self.phaseNote = phaseNote
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let titleLabel = UILabel()
        titleLabel.text = screenTitle.uppercased()
        titleLabel.font = Theme.labelFont(size: 28, weight: .bold)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.textAlignment = .center

        let noteLabel = UILabel()
        noteLabel.text = phaseNote
        noteLabel.font = Theme.labelFont(size: 15)
        noteLabel.textColor = Theme.textSecondary
        noteLabel.textAlignment = .center
        noteLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, noteLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40)
        ])
    }
}
