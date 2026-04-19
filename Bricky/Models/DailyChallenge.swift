import Foundation

/// A daily build challenge generated deterministically from the date
struct DailyChallenge: Identifiable, Codable {
    var id: String
    var date: Date
    var projectName: String
    var projectCategory: String
    var projectDifficulty: String
    var estimatedTime: String
    var imageSystemName: String
    var pieceCount: Int
    var isCompleted: Bool
    var completionTime: TimeInterval?
    var startedAt: Date?

    init(
        id: String = UUID().uuidString,
        date: Date = Date(),
        projectName: String,
        projectCategory: String,
        projectDifficulty: String,
        estimatedTime: String,
        imageSystemName: String,
        pieceCount: Int,
        isCompleted: Bool = false,
        completionTime: TimeInterval? = nil,
        startedAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.projectName = projectName
        self.projectCategory = projectCategory
        self.projectDifficulty = projectDifficulty
        self.estimatedTime = estimatedTime
        self.imageSystemName = imageSystemName
        self.pieceCount = pieceCount
        self.isCompleted = isCompleted
        self.completionTime = completionTime
        self.startedAt = startedAt
    }

    /// The date string used as a deterministic seed (yyyy-MM-dd)
    var dateKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Formatted completion time (e.g., "5:23")
    var formattedCompletionTime: String? {
        guard let time = completionTime else { return nil }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// A puzzle challenge where user guesses a build from clues
struct BuildPuzzle: Identifiable {
    let id = UUID()
    let project: LegoProject
    let clues: [String]
    var revealedClues: Int
    var isGuessed: Bool
    var attempts: Int

    init(project: LegoProject, clues: [String]) {
        self.project = project
        self.clues = clues
        self.revealedClues = 1
        self.isGuessed = false
        self.attempts = 0
    }

    var currentClue: String? {
        guard revealedClues > 0, revealedClues <= clues.count else { return nil }
        return clues[revealedClues - 1]
    }

    var allRevealedClues: [String] {
        Array(clues.prefix(revealedClues))
    }

    var canRevealMore: Bool {
        revealedClues < clues.count
    }

    /// Score based on how few clues were needed (max 100)
    var score: Int {
        guard isGuessed else { return 0 }
        let maxScore = 100
        let penalty = (revealedClues - 1) * 20
        return max(maxScore - penalty - (attempts * 5), 10)
    }
}
