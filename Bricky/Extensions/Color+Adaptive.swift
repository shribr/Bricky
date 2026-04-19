import SwiftUI
import UIKit

/// Adaptive color helpers for legibility in both light and dark mode.
extension Color {
    /// Pick black or white as the most readable foreground on the given
    /// background using YIQ luminance. Threshold ~0.6 favors black on
    /// medium/light tints (yellow, lime, tan) which read poorly with white.
    static func bestForegroundOn(_ background: Color) -> Color {
        let ui = UIColor(background)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        // YIQ luminance per WCAG-ish heuristic
        let yiq = (r * 0.299) + (g * 0.587) + (b * 0.114)
        return yiq >= 0.6 ? .black : .white
    }

    /// Brand orange tuned for label legibility — darker in light mode, brighter in dark.
    static var legoOrangeLabel: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(Color.legoOrange)
                : UIColor(red: 0.76, green: 0.27, blue: 0.05, alpha: 1.0) // ~#C2410C
        })
    }

    /// Brand yellow tuned for label legibility — darker in light mode, brighter in dark.
    static var legoYellowLabel: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(Color.legoYellow)
                : UIColor(red: 0.63, green: 0.39, blue: 0.02, alpha: 1.0) // ~#A16207
        })
    }
}
