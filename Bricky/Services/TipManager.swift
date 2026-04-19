import Foundation

/// Tracks which contextual tips and feature hints the user has seen.
/// UserDefaults-backed so tips persist across launches but only show once.
@MainActor
final class TipManager: ObservableObject {
    static let shared = TipManager()

    private let defaults = UserDefaults.standard
    private let prefix = "tip_seen_"

    /// All available tip identifiers
    enum Tip: String, CaseIterable {
        case firstScan = "first_scan"
        case firstBuildSuggestion = "first_build_suggestion"
        case firstCommunityVisit = "first_community"
        case firstPuzzle = "first_puzzle"
        case firstInventorySave = "first_inventory_save"
        case dailyChallenge = "daily_challenge"
        case timedBuild = "timed_build"
        case scanModes = "scan_modes"
        case buildStreak = "build_streak"
        case catalogFilters = "catalog_filters"
    }

    /// Check whether a tip has been shown
    func hasSeenTip(_ tip: Tip) -> Bool {
        defaults.bool(forKey: prefix + tip.rawValue)
    }

    /// Mark a tip as shown
    func markSeen(_ tip: Tip) {
        defaults.set(true, forKey: prefix + tip.rawValue)
        objectWillChange.send()
    }

    /// Check if tip should show (not yet seen) and mark it as seen
    func shouldShow(_ tip: Tip) -> Bool {
        if hasSeenTip(tip) { return false }
        return true
    }

    /// Reset all tips (e.g. for "Show Tips Again" in settings)
    func resetAll() {
        for tip in Tip.allCases {
            defaults.removeObject(forKey: prefix + tip.rawValue)
        }
        objectWillChange.send()
    }

    /// Reset a single tip so it shows again
    func reset(_ tip: Tip) {
        defaults.removeObject(forKey: prefix + tip.rawValue)
        objectWillChange.send()
    }
}
