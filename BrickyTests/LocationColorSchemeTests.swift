import XCTest
import SwiftUI
@testable import Bricky

/// Verifies the purple/lavender location scheme adapts between light and dark
/// so foreground text/icons keep legible contrast against their paired fill.
final class LocationColorSchemeTests: XCTestCase {

    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    func testLegoPurpleAdaptsBetweenLightAndDark() {
        let purple = UIColor(Color.legoPurple)
        let lightResolved = purple.resolvedColor(with: light)
        let darkResolved = purple.resolvedColor(with: dark)
        XCTAssertNotEqual(lightResolved, darkResolved,
                          "legoPurple must resolve to different colors per interface style")
    }

    func testLegoLavenderAdaptsBetweenLightAndDark() {
        let lavender = UIColor(Color.legoLavender)
        let lightResolved = lavender.resolvedColor(with: light)
        let darkResolved = lavender.resolvedColor(with: dark)
        XCTAssertNotEqual(lightResolved, darkResolved,
                          "legoLavender must resolve to different colors per interface style")
    }

    /// The foreground (legoPurple) and its background (legoLavender) must have a
    /// meaningful luminance gap in each mode — never light-on-light or dark-on-dark.
    func testForegroundBackgroundContrastInBothModes() {
        for traits in [light, dark] {
            let fg = UIColor(Color.legoPurple).resolvedColor(with: traits)
            let bg = UIColor(Color.legoLavender).resolvedColor(with: traits)
            let gap = abs(luminance(of: fg) - luminance(of: bg))
            XCTAssertGreaterThan(gap, 0.3,
                "Insufficient contrast between legoPurple and legoLavender in \(traits.userInterfaceStyle == .dark ? "dark" : "light") mode")
        }
    }

    /// Relative luminance (WCAG-style) of a resolved color.
    private func luminance(of color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}
