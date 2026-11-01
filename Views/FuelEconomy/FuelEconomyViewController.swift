import UIKit

final class FuelEconomyViewController: PlaceholderViewController {
    init() {
        super.init(
            screenTitle: "Fuel Economy",
            phaseNote: "Current/average consumption breakdown, since-reset trip fuel\nand ECU-vs-calculated source tracking arrive in Phase 4."
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}
