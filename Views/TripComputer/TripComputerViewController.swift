import UIKit

final class TripComputerViewController: PlaceholderViewController {
    init() {
        super.init(
            screenTitle: "Trip Computer",
            phaseNote: "Full trip computer with current-trip / since-reset averages\nand persistent trip history arrives in Phase 4."
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}
