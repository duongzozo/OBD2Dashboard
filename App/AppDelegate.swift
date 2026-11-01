import UIKit

/// Classic AppDelegate-driven app lifecycle (no SceneDelegate / multi-window
/// support) — this keeps the app fully compatible down to iOS 12, where
/// UIScene doesn't exist, while still running fine through iOS 17.
@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = Theme.background
        window.rootViewController = RootTabBarController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
