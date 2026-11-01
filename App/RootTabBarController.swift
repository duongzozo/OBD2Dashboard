import UIKit

/// The 7-screen navigation shell from the spec: Dashboard, Live Data, Fuel
/// Economy, Diagnostic, Trip Computer, Vehicle Information, Settings.
/// Text-only tab titles are used deliberately — SF Symbols require iOS 13+
/// and this project's minimum deployment target is iOS 12.
final class RootTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        tabBar.barStyle = .black
        tabBar.barTintColor = Theme.surface
        tabBar.tintColor = Theme.accent
        tabBar.unselectedItemTintColor = Theme.textTertiary
        tabBar.isTranslucent = false

        viewControllers = [
            wrap(DashboardViewController(), title: "Dashboard"),
            wrap(LiveDataViewController(), title: "Live Data"),
            wrap(FuelEconomyViewController(), title: "Fuel Economy"),
            wrap(DiagnosticViewController(), title: "Diagnostic"),
            wrap(TripComputerViewController(), title: "Trip Computer"),
            wrap(VehicleInfoViewController(), title: "Vehicle Info"),
            wrap(SettingsViewController(), title: "Settings")
        ]
    }

    private func wrap(_ viewController: UIViewController, title: String) -> UIViewController {
        viewController.tabBarItem = UITabBarItem(title: title, image: nil, selectedImage: nil)
        return viewController
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var shouldAutorotate: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
}
