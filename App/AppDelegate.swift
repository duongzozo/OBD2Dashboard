import UIKit

/// Classic AppDelegate-driven app lifecycle (no SceneDelegate / multi-window
/// support) — this keeps the app fully compatible down to iOS 12, where
/// UIScene doesn't exist, while still running fine through iOS 17.
@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Theme.isNightMode = SettingsStore.shared.settings.value.nightModeEnabled

        // A cockpit display must not sleep while driving, unless the driver
        // has asked to save power.
        SettingsStore.shared.settings.observe { settings in
            application.isIdleTimerDisabled = !settings.powerSaveModeEnabled
        }

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = Theme.background
        window.rootViewController = RootTabBarController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    /// Recreates every screen so they pick up the current theme, staying on
    /// the same tab. The telemetry stream is app-wide and carries on regardless.
    func rebuildInterface() {
        let selectedIndex = (window?.rootViewController as? UITabBarController)?.selectedIndex ?? 0
        let root = RootTabBarController()
        window?.rootViewController = root
        root.selectedIndex = selectedIndex
    }
}
