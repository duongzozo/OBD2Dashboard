import UIKit

final class LiveDataViewController: PlaceholderViewController {
    init() {
        super.init(
            screenTitle: "Live Data",
            phaseNote: "Customizable PID list, gauges/charts, logging and CSV export\narrive in Phase 3 once the real OBD-II engine is wired up."
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}
