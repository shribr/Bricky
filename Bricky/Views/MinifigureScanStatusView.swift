import SwiftUI

/// Animated overlay shown during the cloud minifigure-identification call.
/// Cycles through plausible analysis stages so the user sees progressive
/// activity instead of a single static spinner.
///
/// Driven by `TimelineView(.periodic)` — SwiftUI's purpose-built clock for
/// time-driven UI. More reliable than Combine timers or `Task.sleep` loops,
/// which can be cancelled by SwiftUI view-graph churn during the scan.
struct MinifigureScanStatusView: View {
    static let defaultStages: [String] = [
        "Locating minifigure…",
        "Analyzing torso & uniform…",
        "Reading facial features…",
        "Matching colors & printing…",
        "Estimating theme & year…",
        "Ranking catalog candidates…"
    ]

    let stages: [String]
    let interval: TimeInterval

    /// Captured at construction so `TimelineView` ticks compute elapsed
    /// time deterministically. SwiftUI `@State` is not used because we
    /// derive the active stage purely from wall-clock delta.
    private let startedAt: Date

    init(stages: [String] = MinifigureScanStatusView.defaultStages,
         interval: TimeInterval = 5.0) {
        self.stages = stages
        self.interval = interval
        self.startedAt = Date()
    }

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 0.25)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let target = stages.isEmpty
                ? 0
                : min(Int(elapsed / interval), stages.count - 1)

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                Text("Identifying minifigure…")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(stages.isEmpty ? "" : stages[target])
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 22)
                    .id(target) // re-trigger transition on each change
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeInOut(duration: 0.35), value: target)
            }
            .padding(.horizontal, 28)
        }
    }
}

#Preview {
    ZStack {
        Color.black
        MinifigureScanStatusView()
    }
}
