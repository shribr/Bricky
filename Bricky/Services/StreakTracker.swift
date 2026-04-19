import Foundation

/// Tracks consecutive days of building activity using UserDefaults
final class StreakTracker: ObservableObject {
    static let shared = StreakTracker()

    private let defaults = UserDefaults.standard
    private let currentStreakKey = "streak_currentCount"
    private let longestStreakKey = "streak_longestCount"
    private let lastActiveDateKey = "streak_lastActiveDate"

    @Published var currentStreak: Int
    @Published var longestStreak: Int
    @Published var lastActiveDate: Date?

    private init() {
        currentStreak = defaults.integer(forKey: currentStreakKey)
        longestStreak = defaults.integer(forKey: longestStreakKey)
        if let timestamp = defaults.object(forKey: lastActiveDateKey) as? Date {
            lastActiveDate = timestamp
        }
        validateStreak()
    }

    /// Record a build activity for today. Call when user completes a build step, scan, or challenge.
    func recordActivity() {
        let today = Calendar.current.startOfDay(for: Date())

        if let last = lastActiveDate {
            let lastDay = Calendar.current.startOfDay(for: last)
            if lastDay == today {
                // Already recorded today
                return
            }
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
            if lastDay == Calendar.current.startOfDay(for: yesterday) {
                // Consecutive day
                currentStreak += 1
            } else {
                // Streak broken, start fresh
                currentStreak = 1
            }
        } else {
            // First activity ever
            currentStreak = 1
        }

        lastActiveDate = today
        if currentStreak > longestStreak {
            longestStreak = currentStreak
        }
        save()
    }

    /// Check if the streak is still valid (not broken by missing a day)
    func validateStreak() {
        guard let last = lastActiveDate else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let lastDay = Calendar.current.startOfDay(for: last)

        if lastDay == today {
            // Active today, streak is valid
            return
        }

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        if lastDay < Calendar.current.startOfDay(for: yesterday) {
            // Missed more than one day — streak broken
            currentStreak = 0
            save()
        }
    }

    /// Whether the user has been active today
    var isActiveToday: Bool {
        guard let last = lastActiveDate else { return false }
        return Calendar.current.isDateInToday(last)
    }

    /// Streak status message for display
    var statusMessage: String {
        if currentStreak == 0 {
            return "Start building to begin a streak!"
        } else if isActiveToday {
            return "\(currentStreak) day streak! 🔥"
        } else {
            return "\(currentStreak) day streak — build today to keep it!"
        }
    }

    func reset() {
        currentStreak = 0
        longestStreak = 0
        lastActiveDate = nil
        save()
    }

    private func save() {
        defaults.set(currentStreak, forKey: currentStreakKey)
        defaults.set(longestStreak, forKey: longestStreakKey)
        defaults.set(lastActiveDate, forKey: lastActiveDateKey)
    }
}
