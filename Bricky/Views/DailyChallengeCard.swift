import SwiftUI

/// Daily challenge card for the home view
struct DailyChallengeCard: View {
    @ObservedObject private var challengeService = DailyChallengeService.shared
    @ObservedObject private var streakTracker = StreakTracker.shared

    var body: some View {
        if let challenge = challengeService.todayChallenge {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3)
                        .foregroundStyle(Color.legoRed)
                    Text("Daily Challenge")
                        .font(.headline)
                    Spacer()
                    if challenge.isCompleted {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: challenge.imageSystemName)
                        .font(.system(size: 32))
                        .foregroundStyle(Color.legoRed.opacity(0.7))
                        .frame(width: 50, height: 50)
                        .background(Color.legoRed.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(challenge.projectName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Label(challenge.projectDifficulty, systemImage: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Label("\(challenge.pieceCount) pieces", systemImage: "cube")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Label(challenge.estimatedTime, systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                if challenge.isCompleted {
                    if let time = challenge.formattedCompletionTime {
                        HStack {
                            Image(systemName: "stopwatch")
                            Text("Completed in \(time)")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.green)
                    }
                } else if challenge.startedAt != nil {
                    Text("In progress...")
                        .font(.caption)
                        .foregroundStyle(Color.legoRed)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
    }
}

/// Streak badge for the home view
struct StreakBadgeView: View {
    @ObservedObject private var streakTracker = StreakTracker.shared

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(streakTracker.currentStreak > 0 ? Color.orange.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: streakTracker.currentStreak > 0 ? "flame.fill" : "flame")
                    .font(.title3)
                    .foregroundStyle(streakTracker.currentStreak > 0 ? .orange : .gray)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(streakTracker.currentStreak)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("day streak")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if streakTracker.longestStreak > streakTracker.currentStreak {
                    Text("Best: \(streakTracker.longestStreak) days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if streakTracker.isActiveToday {
                    Text("Active today")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if streakTracker.currentStreak > 0 {
                    Text("Build today to keep it!")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}
