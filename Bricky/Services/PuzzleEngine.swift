import Foundation

/// Engine that generates build puzzles and daily challenges from the project catalog
final class PuzzleEngine: ObservableObject {
    static let shared = PuzzleEngine()

    @Published var currentPuzzle: BuildPuzzle?
    @Published var puzzleHistory: [PuzzleResult] = []
    @Published var totalScore: Int = 0

    private let defaults = UserDefaults.standard
    private let scoreKey = "puzzle_totalScore"
    private let historyKey = "puzzle_history"

    struct PuzzleResult: Codable, Identifiable {
        let id: String
        let projectName: String
        let score: Int
        let cluesUsed: Int
        let date: Date
    }

    private init() {
        totalScore = defaults.integer(forKey: scoreKey)
        if let data = defaults.data(forKey: historyKey),
           let history = try? JSONDecoder().decode([PuzzleResult].self, from: data) {
            puzzleHistory = history
        }
    }

    /// Generate a new puzzle from a random project
    func generatePuzzle() {
        let projects = BuildSuggestionEngine.shared.allProjects
        guard !projects.isEmpty else { return }

        let project = projects.randomElement()!
        let clues = generateClues(for: project)
        currentPuzzle = BuildPuzzle(project: project, clues: clues)
    }

    /// Reveal the next clue
    func revealNextClue() {
        guard var puzzle = currentPuzzle, puzzle.canRevealMore else { return }
        puzzle.revealedClues += 1
        currentPuzzle = puzzle
    }

    /// Submit a guess
    func submitGuess(_ guess: String) -> Bool {
        guard var puzzle = currentPuzzle else { return false }
        puzzle.attempts += 1

        let normalizedGuess = guess.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAnswer = puzzle.project.name.lowercased()

        if normalizedGuess == normalizedAnswer || normalizedAnswer.contains(normalizedGuess) {
            puzzle.isGuessed = true
            currentPuzzle = puzzle
            recordResult(puzzle)
            return true
        }

        currentPuzzle = puzzle
        return false
    }

    /// Give up and reveal the answer
    func giveUp() {
        guard var puzzle = currentPuzzle else { return }
        puzzle.isGuessed = true
        puzzle.revealedClues = puzzle.clues.count
        currentPuzzle = puzzle
        // No score for giving up
    }

    /// Get available answer choices for multiple-choice mode
    func getAnswerChoices(for puzzle: BuildPuzzle, count: Int = 4) -> [String] {
        let projects = BuildSuggestionEngine.shared.allProjects
        var choices = [puzzle.project.name]

        let sameCategory = projects.filter {
            $0.category == puzzle.project.category && $0.name != puzzle.project.name
        }.shuffled()

        for project in sameCategory where choices.count < count {
            choices.append(project.name)
        }

        // Fill remaining with random projects
        let others = projects.filter { !choices.contains($0.name) }.shuffled()
        for project in others where choices.count < count {
            choices.append(project.name)
        }

        return choices.shuffled()
    }

    private func generateClues(for project: LegoProject) -> [String] {
        var clues: [String] = []

        // Clue 1: Category
        clues.append("Category: \(project.category.rawValue)")

        // Clue 2: Difficulty
        clues.append("Difficulty: \(project.difficulty.rawValue)")

        // Clue 3: Piece count
        let totalPieces = project.requiredPieces.reduce(0) { $0 + $1.quantity }
        clues.append("Total pieces needed: \(totalPieces)")

        // Clue 4: Estimated time
        clues.append("Estimated build time: \(project.estimatedTime)")

        // Clue 5: First letter
        clues.append("Starts with the letter '\(project.name.prefix(1).uppercased())'")

        return clues
    }

    private func recordResult(_ puzzle: BuildPuzzle) {
        let result = PuzzleResult(
            id: UUID().uuidString,
            projectName: puzzle.project.name,
            score: puzzle.score,
            cluesUsed: puzzle.revealedClues,
            date: Date()
        )
        puzzleHistory.insert(result, at: 0)
        totalScore += puzzle.score

        // Persist
        defaults.set(totalScore, forKey: scoreKey)
        if let data = try? JSONEncoder().encode(puzzleHistory) {
            defaults.set(data, forKey: historyKey)
        }

        // Record streak activity
        StreakTracker.shared.recordActivity()
    }
}
