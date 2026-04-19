import SwiftUI

/// Timer overlay for timed build mode on instructions
struct BuildTimerView: View {
    let estimatedTime: String
    @Binding var isTimerActive: Bool
    var onComplete: () -> Void

    @State private var elapsedSeconds: Int = 0
    @State private var isPaused: Bool = false
    @State private var timer: Timer?
    @State private var showResult: Bool = false

    private var estimatedMinutes: Int {
        // Parse "15 min", "25 min", etc.
        let digits = estimatedTime.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits) ?? 15
    }

    private var targetSeconds: Int {
        estimatedMinutes * 60
    }

    private var progress: Double {
        guard targetSeconds > 0 else { return 0 }
        return min(Double(elapsedSeconds) / Double(targetSeconds), 1.0)
    }

    private var isOvertime: Bool {
        elapsedSeconds > targetSeconds
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Timer display
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .foregroundStyle(isOvertime ? .red : Color.legoRed)

                    Text(formattedTime)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(isOvertime ? .red : .primary)
                }

                // Target time
                Text("/ \(estimatedTime)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                // Controls
                HStack(spacing: 12) {
                    Button {
                        togglePause()
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.title3)
                            .foregroundStyle(Color.legoRed)
                    }

                    Button {
                        completeTimer()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }

                    Button {
                        stopTimer()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOvertime ? Color.red : Color.legoRed)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(.linear(duration: 0.5), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
        .alert("Build Complete!", isPresented: $showResult) {
            Button("Done") {
                isTimerActive = false
            }
        } message: {
            if isOvertime {
                Text("Time: \(formattedTime) (over estimate by \(formattedOvertime))")
            } else {
                Text("Time: \(formattedTime) — under the \(estimatedTime) estimate!")
            }
        }
    }

    private var formattedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var formattedOvertime: String {
        let overtime = elapsedSeconds - targetSeconds
        let minutes = overtime / 60
        let seconds = overtime % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if !isPaused {
                elapsedSeconds += 1
            }
        }
    }

    private func togglePause() {
        isPaused.toggle()
        HapticManager.selection()
    }

    private func completeTimer() {
        timer?.invalidate()
        showResult = true
        onComplete()
        StreakTracker.shared.recordActivity()
        HapticManager.notification(.success)
    }

    private func stopTimer() {
        timer?.invalidate()
        isTimerActive = false
        HapticManager.impact()
    }
}
