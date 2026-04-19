import SwiftUI

/// Visual guide explaining the scanning UI phases and controls
struct ScanGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private let pages: [GuidePage] = [
        GuidePage(
            icon: "video.fill",
            iconColor: .blue,
            title: "Phase 1: Live Preview",
            subtitle: "See what the camera detects in real time",
            steps: [
                GuideStep(icon: "video.fill", text: "Tap the blue video button to start the live camera preview"),
                GuideStep(icon: "viewfinder", text: "Point your camera at LEGO pieces — bounding boxes appear around detected bricks"),
                GuideStep(icon: "eye.fill", text: "This phase is for aiming only — no pieces are recorded yet"),
                GuideStep(icon: "arrow.right.circle.fill", text: "Once you see pieces highlighted, you're ready for Phase 2")
            ]
        ),
        GuidePage(
            icon: "camera.fill",
            iconColor: .red,
            title: "Phase 2: Capture & Identify",
            subtitle: "Tap to photograph and catalog your pieces",
            steps: [
                GuideStep(icon: "camera.fill", text: "The button turns red — tap it to capture and identify pieces"),
                GuideStep(icon: "plus.circle.fill", text: "Each tap analyzes the current view and adds new pieces to your inventory"),
                GuideStep(icon: "arrow.triangle.2.circlepath", text: "Tap multiple times as you rearrange pieces to find more"),
                GuideStep(icon: "checkmark.circle.fill", text: "A green badge confirms how many pieces were added each time")
            ]
        ),
        GuidePage(
            icon: "slider.horizontal.3",
            iconColor: .orange,
            title: "Controls",
            subtitle: "Manage your scanning session",
            steps: [
                GuideStep(icon: "pause.circle.fill", text: "Pause — temporarily freezes the live preview. Tap Resume to continue."),
                GuideStep(icon: "stop.circle.fill", text: "Stop — ends the session and turns off the camera. Your pieces are kept."),
                GuideStep(icon: "plus.circle.fill", text: "Manual — add a piece by hand if the camera doesn't detect it"),
                GuideStep(icon: "square.and.arrow.down.fill", text: "Save — save your scanned inventory for later")
            ]
        ),
        GuidePage(
            icon: "eye.fill",
            iconColor: .green,
            title: "View Results",
            subtitle: "Check your scanned inventory at any time",
            steps: [
                GuideStep(icon: "text.badge.checkmark", text: "\"View Results\" appears in the top-right corner after your first capture"),
                GuideStep(icon: "hand.tap.fill", text: "Tap it anytime — even while scanning — to see what you've found so far"),
                GuideStep(icon: "arrow.uturn.backward", text: "You can go back and keep scanning after viewing results"),
                GuideStep(icon: "cube.fill", text: "The button shows once you have at least one captured piece")
            ]
        ),
        GuidePage(
            icon: "list.bullet.rectangle.portrait",
            iconColor: .purple,
            title: "Results Screen",
            subtitle: "Your complete scanned inventory",
            steps: [
                GuideStep(icon: "chart.bar.fill", text: "See totals, unique types, color breakdown, and confidence scores"),
                GuideStep(icon: "magnifyingglass", text: "Search, filter by category, and sort pieces however you like"),
                GuideStep(icon: "mappin.circle.fill", text: "Tap a piece to see where it was detected in the original photo"),
                GuideStep(icon: "lightbulb.fill", text: "Use your inventory to get AI-powered build suggestions")
            ]
        )
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        guidePageView(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Page indicator
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.blue : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 16)

                // Navigation buttons
                HStack {
                    if currentPage > 0 {
                        Button("Previous") {
                            withAnimation { currentPage -= 1 }
                        }
                        .foregroundStyle(.blue)
                    }

                    Spacer()

                    if currentPage < pages.count - 1 {
                        Button("Next") {
                            withAnimation { currentPage += 1 }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                    } else {
                        Button("Got It") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(.blue)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("How to Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func guidePageView(_ page: GuidePage) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header icon
                Image(systemName: page.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(page.iconColor)
                    .padding(.top, 24)

                VStack(spacing: 8) {
                    Text(page.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(page.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Steps
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(page.steps.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(page.iconColor.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: page.steps[index].icon)
                                    .font(.callout)
                                    .foregroundStyle(page.iconColor)
                            }

                            Text(page.steps[index].text)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 10)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct GuidePage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let steps: [GuideStep]
}

private struct GuideStep {
    let icon: String
    let text: String
}
