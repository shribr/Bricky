import SwiftUI

// NOTE: The previous segment-grid overlay was removed when the scan flow
// switched to the continuous mesh-overlay design. This file now holds only
// the post-scan completion modal that `CameraScanView` presents when a scan
// finishes. See `PileMeshOverlayView` for the live overlay.

// MARK: - Scan Complete Modal

struct DetailedScanCompleteView: View {
    let totalPieces: Int
    let uniquePieces: Int
    let onViewResults: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.pulse)

            Text("Scan Complete")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            HStack(spacing: 24) {
                statItem(value: "\(totalPieces)", label: "Total Pieces")
                statItem(value: "\(uniquePieces)", label: "Unique Types")
            }

            Button {
                onViewResults()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle.fill")
                    Text("View Results")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color.blue)
                .clipShape(Capsule())
            }
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .padding(40)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
