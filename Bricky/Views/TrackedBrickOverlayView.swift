import SwiftUI

/// A world-anchored brick marker, already projected to the screen.
/// `point` is NORMALIZED (0–1), origin TOP-LEFT.
struct BrickScreenMarker: Identifiable {
    let id: UUID
    let point: CGPoint
    let color: LegoColor
    let label: String?
}

/// Persistent overlay marking bricks that have already been counted during a
/// world-tracked pile scan. Each marker stays anchored to its physical brick as
/// the camera moves (the caller updates `markers` from re-projected world
/// positions), so the user can see exactly which pieces are already scanned.
struct TrackedBrickOverlayView: View {
    let markers: [BrickScreenMarker]

    var body: some View {
        GeometryReader { geo in
            ForEach(markers) { marker in
                CountedBrickMarker(color: marker.color)
                    .position(
                        x: marker.point.x * geo.size.width,
                        y: marker.point.y * geo.size.height
                    )
                    .accessibilityLabel("Counted: \(marker.label ?? "brick")")
            }
            .animation(.easeInOut(duration: 0.15), value: markers.map(\.id))
        }
        .allowsHitTesting(false)
    }
}

/// The visual for a single counted brick: the brick's own LEGO color filling an
/// inner disc, wrapped by a green "counted" ring, with a green checkmark badge.
private struct CountedBrickMarker: View {
    let color: LegoColor

    var body: some View {
        ZStack {
            // Inner disc tinted with the brick's own LEGO color, plus a white
            // hairline so it stays legible over any camera background.
            Circle()
                .fill(Color.legoColor(color).opacity(0.85))
                .overlay(
                    Circle().stroke(Color.white.opacity(0.9), lineWidth: 0.5)
                )
                .frame(width: 24, height: 24)

            // Green "counted" ring around the disc.
            Circle()
                .stroke(Color.green, lineWidth: 3)
                .frame(width: 24, height: 24)

            // Checkmark badge offset to the top-trailing corner.
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
                .shadow(color: .black.opacity(0.4), radius: 1.5, x: 0, y: 0.5)
                .offset(x: 12, y: -12)
        }
    }
}
