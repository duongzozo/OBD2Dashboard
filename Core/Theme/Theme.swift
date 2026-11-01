import UIKit

/// Hardcoded automotive-cockpit color palette. iOS 12 has no dark-mode
/// concept (semantic/dynamic colors require iOS 13's UIColor trait
/// resolution), so the whole app is intentionally always-dark via explicit
/// constants rather than relying on the system appearance.
struct Theme {
    static var isNightMode = false

    static var background: UIColor { UIColor(red: 0.047, green: 0.059, blue: 0.075, alpha: 1) }
    static var surface: UIColor { UIColor(red: 0.09, green: 0.11, blue: 0.13, alpha: 1) }
    static var surfaceElevated: UIColor { UIColor(red: 0.13, green: 0.15, blue: 0.18, alpha: 1) }
    static var hairline: UIColor { UIColor(white: 1, alpha: 0.08) }

    /// Primary accent — cyan in normal mode, switches to red-tinted in
    /// night-driving mode to preserve the driver's night vision.
    static var accent: UIColor {
        isNightMode ? UIColor(red: 0.85, green: 0.16, blue: 0.16, alpha: 1)
                    : UIColor(red: 0.0, green: 0.90, blue: 0.79, alpha: 1)
    }

    static var accentSecondary: UIColor {
        isNightMode ? UIColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1)
                    : UIColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1)
    }

    static var textPrimary: UIColor { UIColor(white: 0.96, alpha: 1) }
    static var textSecondary: UIColor { UIColor(white: 0.62, alpha: 1) }
    static var textTertiary: UIColor { UIColor(white: 0.42, alpha: 1) }

    static var warning: UIColor { UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1) }
    static var danger: UIColor { UIColor(red: 0.95, green: 0.23, blue: 0.23, alpha: 1) }
    static var success: UIColor { UIColor(red: 0.2, green: 0.85, blue: 0.45, alpha: 1) }
    static var gaugeTrack: UIColor { UIColor(white: 1, alpha: 0.10) }

    // MARK: - Fonts (large, legible-at-a-distance digital cockpit type)

    static func digitFont(size: CGFloat, weight: UIFont.Weight = .bold) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    static func labelFont(size: CGFloat, weight: UIFont.Weight = .medium) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }
}
