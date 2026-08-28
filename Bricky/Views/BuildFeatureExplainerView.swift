import SwiftUI

/// Explains the "See What You Can Build" feature and provides a launch path.
/// Presented from the Home promo card.
struct BuildFeatureExplainerView: View {
    /// Whether a recent scan exists, so we can offer a direct launch.
    let hasRecentPieces: Bool
    let onLaunchBuilds: () -> Void
    let onStartScan: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(spacing: 16) {
                        stepRow(
                            number: 1,
                            icon: "camera.viewfinder",
                            title: "Scan your bricks",
                            detail: "Use the Scanner to capture a pile of LEGO pieces. Bricky identifies every part and color."
                        )
                        stepRow(
                            number: 2,
                            icon: "hammer.fill",
                            title: "See what you can build",
                            detail: "On the Scan Results screen, tap “See What You Can Build.” Bricky matches your pieces to buildable projects."
                        )
                        stepRow(
                            number: 3,
                            icon: "cube.transparent",
                            title: "Follow 3D instructions",
                            detail: "Open any project for step-by-step 3D instructions you can rotate and zoom — built from the exact pieces you own."
                        )
                    }

                    whereToFind

                    launchButtons
                }
                .padding()
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Build Ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.legoOrange.opacity(0.15))
                    .frame(width: 84, height: 84)
                Image(systemName: "hammer.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.legoOrange)
            }
            Text("See What You Can Build")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text("Turn a pile of bricks into projects you can actually build — with guided 3D instructions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func stepRow(number: Int, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.legoBlue)
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var whereToFind: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(Color.legoBlue)
            Text("Find it any time on the **Scan Results** screen after a scan, under the **See What You Can Build** button.")
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var launchButtons: some View {
        VStack(spacing: 12) {
            if hasRecentPieces {
                Button(action: onLaunchBuilds) {
                    Label("See Ideas from My Last Scan", systemImage: "hammer.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.legoBlue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button(action: onStartScan) {
                    Text("Start a New Scan")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.legoBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            } else {
                Button(action: onStartScan) {
                    Label("Start a Scan", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.legoBlue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

#Preview("No recent scan") {
    BuildFeatureExplainerView(hasRecentPieces: false, onLaunchBuilds: {}, onStartScan: {})
}

#Preview("Has recent scan") {
    BuildFeatureExplainerView(hasRecentPieces: true, onLaunchBuilds: {}, onStartScan: {})
}
