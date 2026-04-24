import SwiftUI

/// Animated overlay shown during minifigure identification.
/// Cycles through plausible analysis stages in a loop so the user always
/// sees progressive activity — never a frozen "stuck" state.
///
/// Driven by `TimelineView(.periodic)` — SwiftUI's purpose-built clock for
/// time-driven UI. More reliable than Combine timers or `Task.sleep` loops,
/// which can be cancelled by SwiftUI view-graph churn during the scan.
struct MinifigureScanStatusView: View {
    static let defaultStages: [String] = [
        "Locating minifigure…",
        "Analyzing torso & uniform…",
        "Matching colors & printing…",
        "Estimating theme & year…",
        "Ranking catalog candidates…",
        "Refining visual match…"
    ]

    let stages: [String]
    let interval: TimeInterval
    /// Optional override message. When non-nil, this is shown instead of
    /// the cycling stage text — used for short-lived pre-scan steps like
    /// "Enhancing image…" that run before the main identification loop.
    var overrideMessage: String?
    /// When true, a cloud validation banner is displayed below the main
    /// status text to indicate the Brickognize service is being queried.
    var showCloudValidation: Bool = false

    /// Captured at construction so `TimelineView` ticks compute elapsed
    /// time deterministically.
    private let startedAt: Date

    init(stages: [String] = MinifigureScanStatusView.defaultStages,
         interval: TimeInterval = 1.5,
         overrideMessage: String? = nil,
         showCloudValidation: Bool = false) {
        self.stages = stages
        self.interval = interval
        self.overrideMessage = overrideMessage
        self.showCloudValidation = showCloudValidation
        self.startedAt = Date()
    }

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 0.25)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let totalCycle = interval * Double(stages.count)
            // Walk through the stages exactly once. After one full cycle,
            // hold on a "still working" message so the user doesn't see
            // the same labels loop forever.
            let pastCycle = elapsed >= totalCycle
            let target = stages.isEmpty
                ? 0
                : pastCycle
                    ? stages.count - 1
                    : min(Int(elapsed / interval), stages.count - 1)

            let cycleLabel = pastCycle
                ? "Still working — almost done…"
                : (stages.isEmpty ? "" : stages[target])
            let label = overrideMessage ?? cycleLabel

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                Text("Identifying minifigure…")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 22)
                    .id(label) // re-trigger transition on each change
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeInOut(duration: 0.35), value: label)

                if showCloudValidation {
                    HStack(spacing: 8) {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.caption.weight(.semibold))
                            .symbolEffect(.pulse, options: .repeating)
                        Text("Validating with Brickognize cloud service…")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.cyan.opacity(0.15)))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
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
