import SwiftUI

/// Build puzzle game view — guess the build from progressive clues
struct PuzzleView: View {
    @ObservedObject private var engine = PuzzleEngine.shared
    @State private var guessText = ""
    @State private var showWrongGuess = false
    @State private var answerChoices: [String] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                DailyChallengeCard()

                FeatureTipView(
                    tip: .firstPuzzle,
                    icon: "puzzlepiece.fill",
                    title: "How Puzzles Work",
                    message: "Read progressive clues about a LEGO build and guess which one it is. Fewer clues = higher score! Tap 'New Puzzle' to start.",
                    color: .purple
                )

                headerSection

                if let puzzle = engine.currentPuzzle {
                    if puzzle.isGuessed {
                        revealedSection(puzzle)
                    } else {
                        puzzleSection(puzzle)
                    }
                } else {
                    startSection
                }

                if !engine.puzzleHistory.isEmpty {
                    historySection
                }
            }
            .padding()
        }
        .navigationTitle("Build Puzzles")
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "puzzlepiece.fill")
                    .font(.title2)
                    .foregroundStyle(Color.legoRed)
                Text("Total Score: \(engine.totalScore)")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Text("\(engine.puzzleHistory.count) puzzles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var startSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 60))
                .foregroundStyle(Color.legoRed.opacity(0.5))

            Text("Can you guess the build?")
                .font(.title3)
                .fontWeight(.semibold)

            Text("You'll get clues one at a time. Fewer clues = higher score!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                engine.generatePuzzle()
                if let puzzle = engine.currentPuzzle {
                    answerChoices = engine.getAnswerChoices(for: puzzle)
                }
            } label: {
                Label("Start Puzzle", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 20)
    }

    private func puzzleSection(_ puzzle: BuildPuzzle) -> some View {
        VStack(spacing: 16) {
            // Silhouette placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 160)

                Image(systemName: "questionmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }

            // Clues revealed so far
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(puzzle.allRevealedClues.enumerated()), id: \.offset) { index, clue in
                    HStack(alignment: .top, spacing: 8) {
                        Text("Clue \(index + 1):")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.legoRed)
                            .frame(width: 55, alignment: .leading)
                        Text(clue)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Multiple choice answers
            VStack(spacing: 8) {
                ForEach(answerChoices, id: \.self) { choice in
                    Button {
                        submitChoice(choice)
                    } label: {
                        Text(choice)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            if showWrongGuess {
                Text("Not quite! Try again or reveal another clue.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Action buttons
            HStack(spacing: 12) {
                if puzzle.canRevealMore {
                    Button {
                        engine.revealNextClue()
                        if let updated = engine.currentPuzzle {
                            answerChoices = engine.getAnswerChoices(for: updated)
                        }
                        showWrongGuess = false
                    } label: {
                        Label("Next Clue", systemImage: "lightbulb")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }

                Button {
                    engine.giveUp()
                } label: {
                    Text("Give Up")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func revealedSection(_ puzzle: BuildPuzzle) -> some View {
        VStack(spacing: 16) {
            Image(systemName: puzzle.project.imageSystemName)
                .font(.system(size: 60))
                .foregroundStyle(Color.legoRed)

            Text(puzzle.project.name)
                .font(.title2)
                .fontWeight(.bold)

            if puzzle.score > 0 {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("+\(puzzle.score) points")
                        .font(.headline)
                        .foregroundStyle(Color.legoRed)
                }
            } else {
                Text("Better luck next time!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(puzzle.project.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                engine.generatePuzzle()
                if let newPuzzle = engine.currentPuzzle {
                    answerChoices = engine.getAnswerChoices(for: newPuzzle)
                }
                showWrongGuess = false
            } label: {
                Label("Next Puzzle", systemImage: "arrow.forward")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 20)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Puzzles")
                .font(.headline)

            ForEach(engine.puzzleHistory.prefix(5)) { result in
                HStack {
                    Text(result.projectName)
                        .font(.subheadline)
                    Spacer()
                    Text("\(result.cluesUsed) clues")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("+\(result.score)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.legoRed)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func submitChoice(_ choice: String) {
        if engine.submitGuess(choice) {
            showWrongGuess = false
            HapticManager.notification(.success)
        } else {
            showWrongGuess = true
            HapticManager.notification(.error)
        }
    }
}
