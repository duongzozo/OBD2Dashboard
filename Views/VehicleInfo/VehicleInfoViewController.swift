import UIKit

final class VehicleInfoViewController: PlaceholderViewController {
    init() {
        super.init(
            screenTitle: "Vehicle Information",
            phaseNote: "VIN, adapter firmware/protocol detection, and supported-PID\nbitmap readout arrive once Bluetooth + the OBD engine exist (Phase 2/3)."
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}
