import SwiftUI

/// Brickit-inspired per-piece overlay box.
///
/// Visual recipe (matches the reference screenshots):
/// • 2pt orange rounded stroke with a soft outer glow
/// • Filled corner accents at all four corners (viewfinder feel)
/// • A small circular badge in the top-left containing a piece icon
/// • No textual labels — the bottom drawer in CameraScanView shows piece names
///
/// Use this as the overlay style for live detections during a scan.
struct BrickitBoundingBoxView: View {
    let frame: CGRect
    let legoColor: LegoColor
    let confidence: Float

    @State private var appeared = false
    @State private var pulse = false

    /// Brickit accent uses warm orange. We keep this constant rather than
    /// pulling from theme so the overlay is recognisable across themes.
    private let accent = Color(red: 1.0, green: 0.45, blue: 0.10)
    private var cornerLength: CGFloat {
        max(8, min(18, min(frame.width, frame.height) * 0.18))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Outer glow
            RoundedRectangle(cornerRadius: 10)
                .stroke(accent.opacity(appeared ? 0.45 : 0), lineWidth: 4)
                .blur(radius: 6)
                .frame(width: frame.width, height: frame.height)

            // Main rounded stroke
            RoundedRectangle(cornerRadius: 10)
                .stroke(accent.opacity(appeared ? 0.95 : 0), lineWidth: 2)
                .frame(width: frame.width, height: frame.height)

            // Corner accents
            cornerAccents

            // Badge
            badge
                .offset(x: -10, y: -10)
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.22)) { appeared = true }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Detected \(legoColor.rawValue) piece, \(Int(confidence * 100)) percent confidence")
    }

    // MARK: - Subviews

    private var cornerAccents: some View {
        let len = cornerLength
        return ZStack {
            // Top-left
            cornerShape(.topLeft, length: len)
            // Top-right
            cornerShape(.topRight, length: len)
                .position(x: frame.width - len / 2, y: len / 2)
            // Bottom-left
            cornerShape(.bottomLeft, length: len)
                .position(x: len / 2, y: frame.height - len / 2)
            // Bottom-right
            cornerShape(.bottomRight, length: len)
                .position(x: frame.width - len / 2, y: frame.height - len / 2)
        }
        .frame(width: frame.width, height: frame.height)
    }

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private func cornerShape(_ corner: Corner, length: CGFloat) -> some View {
        Path { path in
            switch corner {
            case .topLeft:
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))
            case .topRight:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))
                path.addLine(to: CGPoint(x: length, y: length))
            case .bottomLeft:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: length, y: length))
            case .bottomRight:
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: length, y: length))
                path.addLine(to: CGPoint(x: length, y: 0))
            }
        }
        .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        .frame(width: length, height: length)
        .position(x: length / 2, y: length / 2)
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(accent)
                .frame(width: 22, height: 22)
                .shadow(color: accent.opacity(0.6), radius: 4)
            Image(systemName: "cube.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .scaleEffect(pulse ? 1.08 : 1.0)
    }
}
