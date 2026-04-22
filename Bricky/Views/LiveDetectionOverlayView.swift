import SwiftUI

/// Draws bounding boxes over detected bricks on the live camera preview.
/// Bounding boxes are in Vision normalized coordinates (origin bottom-left, 0-1 range)
/// and are converted to SwiftUI coordinates within the overlay geometry.
struct LiveDetectionOverlayView: View {
    let detections: [ObjectRecognitionService.DetectedObject]
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        GeometryReader { geometry in
            ForEach(detections) { detection in
                let frame = visionToScreen(detection.boundingBox, in: geometry.size)
                let screenContour = visionContourToScreen(detection.contourPoints, in: geometry.size)
                switch themeManager.scanOverlayStyle {
                case .brickit:
                    BrickitBoundingBoxView(
                        frame: frame,
                        legoColor: detection.dominantColor,
                        confidence: detection.confidence,
                        contourPoints: screenContour
                    )
                case .clean:
                    CleanBoundingBoxView(
                        frame: frame,
                        label: detection.label,
                        legoColor: detection.dominantColor,
                        confidence: detection.confidence,
                        contourPoints: screenContour
                    )
                case .detailed:
                    DetailedBoundingBoxView(
                        frame: frame,
                        label: detection.label,
                        legoColor: detection.dominantColor,
                        confidence: detection.confidence,
                        contourPoints: screenContour
                    )
                case .minimal:
                    MinimalBoundingBoxView(
                        frame: frame,
                        legoColor: detection.dominantColor,
                        confidence: detection.confidence,
                        contourPoints: screenContour
                    )
                case .none:
                    EmptyView()
                }
            }
        }
    }

    /// Convert Vision normalized rect (origin bottom-left) to screen coordinates (origin top-left)
    private func visionToScreen(_ rect: CGRect, in size: CGSize) -> CGRect {
        let x = rect.origin.x * size.width
        let y = (1 - rect.origin.y - rect.height) * size.height
        let width = rect.width * size.width
        let height = rect.height * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Convert normalized Vision contour points to screen coordinates.
    private func visionContourToScreen(_ points: [CGPoint]?, in size: CGSize) -> [CGPoint]? {
        guard let points, points.count >= 3 else { return nil }
        return points.map { pt in
            CGPoint(x: pt.x * size.width, y: (1 - pt.y) * size.height)
        }
    }
}

// MARK: - Clean Style (white boxes, compact label)

struct CleanBoundingBoxView: View {
    let frame: CGRect
    let label: String
    let legoColor: LegoColor
    let confidence: Float
    var contourPoints: [CGPoint]? = nil
    @State private var appeared = false

    private var accentColor: Color { Color.legoColor(legoColor) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let contour = contourPoints, contour.count >= 3 {
                ContourShape(points: contour, frame: frame)
                    .stroke(Color.white.opacity(appeared ? 0.9 : 0.0), lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .background(
                        ContourShape(points: contour, frame: frame)
                            .fill(Color.white.opacity(appeared ? 0.08 : 0.0))
                    )
            } else {
                Rectangle()
                    .strokeBorder(Color.white.opacity(appeared ? 0.9 : 0.0), lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .background(
                        Rectangle()
                            .fill(Color.white.opacity(appeared ? 0.08 : 0.0))
                    )
            }

            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 8, height: 8)
                Text(shortLabel(label))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.black.opacity(0.7))
            )
            .offset(x: 0, y: -20)
        }
        .position(x: frame.midX, y: frame.midY)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(Int(confidence * 100)) percent confidence")
    }

    private func shortLabel(_ label: String) -> String {
        if label.count <= 12 { return label }
        return String(label.prefix(12))
    }
}

// MARK: - Detailed Style (color-coded, corner accents, confidence badge)

struct DetailedBoundingBoxView: View {
    let frame: CGRect
    let label: String
    let legoColor: LegoColor
    let confidence: Float
    var contourPoints: [CGPoint]? = nil
    @State private var appeared = false

    private var color: Color { Color.legoColor(legoColor) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let contour = contourPoints, contour.count >= 3 {
                // Contour-based highlight fill
                ContourShape(points: contour, frame: frame)
                    .fill(color.opacity(appeared ? 0.15 : 0.0))
                    .frame(width: frame.width, height: frame.height)

                // Contour border with glow
                ContourShape(points: contour, frame: frame)
                    .stroke(color, lineWidth: appeared ? 2.5 : 1.0)
                    .frame(width: frame.width, height: frame.height)
                    .shadow(color: color.opacity(0.6), radius: appeared ? 6 : 0)
            } else {
                // Highlight fill
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(appeared ? 0.15 : 0.0))
                    .frame(width: frame.width, height: frame.height)

                // Color-coded border with glow
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(color, lineWidth: appeared ? 2.5 : 1.0)
                    .frame(width: frame.width, height: frame.height)
                    .shadow(color: color.opacity(0.6), radius: appeared ? 6 : 0)

                // Corner accents
                cornerAccents
            }

            // Label badge with confidence
            HStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                Text("\(Int(confidence * 100))%")
                    .font(.system(size: 9, weight: .medium))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.85))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            )
            .offset(y: -18)
        }
        .position(x: frame.midX, y: frame.midY)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(Int(confidence * 100)) percent confidence")
    }

    private var cornerAccents: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 10))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 10, y: 0))
            }
            .stroke(color, lineWidth: 3)

            Path { path in
                path.move(to: CGPoint(x: frame.width - 10, y: 0))
                path.addLine(to: CGPoint(x: frame.width, y: 0))
                path.addLine(to: CGPoint(x: frame.width, y: 10))
            }
            .stroke(color, lineWidth: 3)

            Path { path in
                path.move(to: CGPoint(x: 0, y: frame.height - 10))
                path.addLine(to: CGPoint(x: 0, y: frame.height))
                path.addLine(to: CGPoint(x: 10, y: frame.height))
            }
            .stroke(color, lineWidth: 3)

            Path { path in
                path.move(to: CGPoint(x: frame.width - 10, y: frame.height))
                path.addLine(to: CGPoint(x: frame.width, y: frame.height))
                path.addLine(to: CGPoint(x: frame.width, y: frame.height - 10))
            }
            .stroke(color, lineWidth: 3)
        }
        .frame(width: frame.width, height: frame.height)
    }
}

// MARK: - Minimal Style (boxes only, no labels)

struct MinimalBoundingBoxView: View {
    let frame: CGRect
    let legoColor: LegoColor
    let confidence: Float
    var contourPoints: [CGPoint]? = nil
    @State private var appeared = false

    private var color: Color { Color.legoColor(legoColor) }

    var body: some View {
        Group {
            if let contour = contourPoints, contour.count >= 3 {
                ContourShape(points: contour, frame: frame)
                    .stroke(color.opacity(appeared ? 0.8 : 0.0), lineWidth: 1.5)
                    .frame(width: frame.width, height: frame.height)
            } else {
                Rectangle()
                    .strokeBorder(color.opacity(appeared ? 0.8 : 0.0), lineWidth: 1.5)
                    .frame(width: frame.width, height: frame.height)
            }
        }
        .position(x: frame.midX, y: frame.midY)
            .onAppear {
                withAnimation(.easeOut(duration: 0.2)) {
                    appeared = true
                }
            }
            .accessibilityLabel("Detected brick, \(Int(confidence * 100)) percent confidence")
    }
}

// MARK: - Contour Shape

/// A `Shape` that draws a closed polygon from screen-space contour points,
/// translated so they are relative to the given frame origin.
struct ContourShape: Shape {
    let points: [CGPoint]
    let frame: CGRect

    func path(in rect: CGRect) -> Path {
        guard points.count >= 3 else { return Path() }
        var path = Path()
        // Translate absolute screen points to be relative to the frame origin
        let translated = points.map { CGPoint(x: $0.x - frame.minX, y: $0.y - frame.minY) }
        path.move(to: translated[0])
        for pt in translated.dropFirst() {
            path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }
}
