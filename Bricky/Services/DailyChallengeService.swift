import Foundation

/// Generates and manages daily build challenges using deterministic date-seeded selection
final class DailyChallengeService: ObservableObject {
    static let shared = DailyChallengeService()

    @Published var todayChallenge: DailyChallenge?
    @Published var challengeHistory: [DailyChallenge] = []

    private let defaults = UserDefaults.standard
    private let historyKey = "daily_challengeHistory"
    private let lastDateKey = "daily_lastChallengeDate"

    private init() {
        loadHistory()
        generateTodayChallenge()
    }

    /// Get or generate today's challenge
    func generateTodayChallenge() {
        let today = todayDateKey()

        // Check if we already have today's challenge
        if let existing = challengeHistory.first(where: { $0.dateKey == today }) {
            todayChallenge = existing
            return
        }

        // Generate deterministically from date
        let projects = BuildSuggestionEngine.shared.allProjects
        guard !projects.isEmpty else { return }

        let index = deterministicIndex(for: today, count: projects.count)
        let project = projects[index]
        let totalPieces = project.requiredPieces.reduce(0) { $0 + $1.quantity }

        let challenge = DailyChallenge(
            id: "daily_\(today)",
            date: Calendar.current.startOfDay(for: Date()),
            projectName: project.name,
            projectCategory: project.category.rawValue,
            projectDifficulty: project.difficulty.rawValue,
            estimatedTime: project.estimatedTime,
            imageSystemName: project.imageSystemName,
            pieceCount: totalPieces
        )

        todayChallenge = challenge
        challengeHistory.insert(challenge, at: 0)
        saveHistory()
    }

    /// Start the daily challenge timer
    func startChallenge() {
        guard var challenge = todayChallenge, challenge.startedAt == nil else { return }
        challenge.startedAt = Date()
        todayChallenge = challenge
        updateInHistory(challenge)
    }

    /// Complete the daily challenge
    func completeChallenge() {
        guard var challenge = todayChallenge, !challenge.isCompleted else { return }

        if let startedAt = challenge.startedAt {
            challenge.completionTime = Date().timeIntervalSince(startedAt)
        }
        challenge.isCompleted = true
        todayChallenge = challenge
        updateInHistory(challenge)

        // Record streak activity
        StreakTracker.shared.recordActivity()
    }

    /// Whether a new challenge is available (different date from last completed)
    var isTodayChallengeNew: Bool {
        guard let challenge = todayChallenge else { return true }
        return !challenge.isCompleted
    }

    /// Completed challenge count
    var completedCount: Int {
        challengeHistory.filter(\.isCompleted).count
    }

    /// Best completion time
    var bestTime: TimeInterval? {
        challengeHistory
            .compactMap(\.completionTime)
            .min()
    }

    var formattedBestTime: String? {
        guard let best = bestTime else { return nil }
        let minutes = Int(best) / 60
        let seconds = Int(best) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Deterministic Selection

    /// Generate a deterministic index from a date string
    private func deterministicIndex(for dateKey: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt64 = 5381
        for char in dateKey.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(char) // djb2
        }
        return Int(hash % UInt64(count))
    }

    private func todayDateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Persistence

    private func loadHistory() {
        if let data = defaults.data(forKey: historyKey),
           let history = try? JSONDecoder().decode([DailyChallenge].self, from: data) {
            challengeHistory = history
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(challengeHistory) {
            defaults.set(data, forKey: historyKey)
        }
    }

    private func updateInHistory(_ challenge: DailyChallenge) {
        if let idx = challengeHistory.firstIndex(where: { $0.id == challenge.id }) {
            challengeHistory[idx] = challenge
        }
        saveHistory()
    }
}
