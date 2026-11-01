import UIKit

final class DiagnosticViewController: PlaceholderViewController {
    init() {
        super.init(
            screenTitle: "Diagnostic",
            phaseNote: "DTC scan (Mode 03/07/0A), freeze frame, and the confirm-before-clear\nworkflow (Mode 04) arrive in Phase 5 with the real OBD-II engine."
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}
