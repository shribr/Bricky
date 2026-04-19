import SwiftUI

/// A dismissable inline tip card shown on first use of a feature.
/// Tracks dismissal via TipManager so each tip only shows once.
struct FeatureTipView: View {
    let tip: TipManager.Tip
    let icon: String
    let title: String
    let message: String
    var color: Color = .blue

    @ObservedObject private var tipManager = TipManager.shared
    @State private var isVisible = false

    var body: some View {
        if isVisible {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        isVisible = false
                    }
                    tipManager.markSeen(tip)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(color.opacity(0.2), lineWidth: 1)
                    )
            )
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }

    init(tip: TipManager.Tip, icon: String, title: String, message: String, color: Color = .blue) {
        self.tip = tip
        self.icon = icon
        self.title = title
        self.message = message
        self.color = color
        // Check immediately if tip should show
        _isVisible = State(initialValue: !TipManager.shared.hasSeenTip(tip))
    }
}
