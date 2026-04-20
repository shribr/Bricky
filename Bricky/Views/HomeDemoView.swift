import SwiftUI

// MARK: - Demo Mode

struct DemoModeView: View {
    @ObservedObject var session: ScanSession
    @Environment(\.dismiss) private var dismiss
    @State private var demoPhase: DemoPhase = .intro
    @State private var navigateToResults = false
    @State private var animatedBoxes: [DemoBox] = []
    @State private var capturedPieceNames: [String] = []
    @State private var showCaptureFlash = false
    @State private var phaseExplanation = ""

    private enum DemoPhase {
        case intro, phase1, transition, phase2, done
    }

    private struct DemoBox: Identifiable {
        let id = UUID()
        var rect: CGRect
        var label: String
        var color: Color
        var opacity: Double = 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch demoPhase {
                case .intro:
                    introView
                case .phase1:
                    phase1View
                case .transition:
                    transitionView
                case .phase2:
                    phase2View
                case .done:
                    doneView
                }
            }
            .navigationTitle("Demo Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $navigateToResults) {
                ScanResultsView(session: session)
            }
        }
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.legoBlue)

            Text("Interactive Demo")
                .font(.title)
                .fontWeight(.bold)

            Text("Watch how \(AppConfig.appName) scans and identifies LEGO pieces in two phases.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                demoStepRow(number: 1, title: "Live Preview", description: "Camera detects bricks in real time", icon: "video.fill", color: .blue)
                demoStepRow(number: 2, title: "Capture & Identify", description: "Tap to photograph and catalog pieces", icon: "camera.fill", color: .red)
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)

            Spacer()

            Button {
                withAnimation { demoPhase = .phase1 }
                startPhase1Animation()
            } label: {
                Text("Start Demo")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Phase 1: Live Preview

    private var phase1View: some View {
        VStack(spacing: 16) {
            // Phase badge
            phaseBadge(number: 1, title: "Live Preview", icon: "video.fill", color: .blue)

            // Simulated camera view
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.9))
                    .aspectRatio(4/3, contentMode: .fit)
                    .overlay {
                        demoBrickPile
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                // Simulated bounding boxes
                GeometryReader { geo in
                    ForEach(animatedBoxes) { box in
                        let rect = CGRect(
                            x: box.rect.origin.x * geo.size.width,
                            y: box.rect.origin.y * geo.size.height,
                            width: box.rect.width * geo.size.width,
                            height: box.rect.height * geo.size.height
                        )
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(box.color, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .overlay(alignment: .topLeading) {
                                Text(box.label)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(box.color.opacity(0.8))
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                    .offset(y: -14)
                            }
                            .position(x: rect.midX, y: rect.midY)
                            .opacity(box.opacity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // "Scanning" indicator
                VStack {
                    HStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("LIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                    }
                    .padding(8)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)

            // Explanation
            Text(phaseExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(minHeight: 40)
                .animation(.easeInOut(duration: 0.3), value: phaseExplanation)

            Spacer()

            Button {
                withAnimation { demoPhase = .transition }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { demoPhase = .phase2 }
                    startPhase2Animation()
                }
            } label: {
                Text("Next: Capture Phase")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Transition

    private var transitionView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.legoYellow)
            Text("Switching to Capture Mode...")
                .font(.title3)
                .fontWeight(.semibold)
            Text("The button turns red — each tap captures and catalogs pieces")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Phase 2: Capture

    private var phase2View: some View {
        VStack(spacing: 16) {
            phaseBadge(number: 2, title: "Capture & Identify", icon: "camera.fill", color: .red)

            // Simulated camera with capture flash
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.9))
                    .aspectRatio(4/3, contentMode: .fit)
                    .overlay {
                        demoBrickPile
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                // Bounding boxes (from phase 1)
                GeometryReader { geo in
                    ForEach(animatedBoxes) { box in
                        let rect = CGRect(
                            x: box.rect.origin.x * geo.size.width,
                            y: box.rect.origin.y * geo.size.height,
                            width: box.rect.width * geo.size.width,
                            height: box.rect.height * geo.size.height
                        )
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(box.color, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .opacity(box.opacity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Flash overlay
                if showCaptureFlash {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 24)

            // Captured pieces list
            if !capturedPieceNames.isEmpty {
                VStack(spacing: 4) {
                    ForEach(capturedPieceNames, id: \.self) { name in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(name)
                                .font(.caption)
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 32)
            }

            Text(phaseExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(minHeight: 40)

            Spacer()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Demo Complete!")
                .font(.title2)
                .fontWeight(.bold)

            Text("\(session.totalPiecesFound) sample pieces identified across \(session.pieces.count) unique types")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                navigateToResults = true
            } label: {
                Text("View Results")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Helpers

    private func phaseBadge(number: Int, title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text("Phase \(number): \(title)")
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color)
        .clipShape(Capsule())
    }

    private func demoStepRow(number: Int, title: String, description: String, icon: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Phase \(number): \(title)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Demo Brick Pile

    /// Simulated pile of LEGO bricks rendered with SwiftUI shapes to make the demo camera view look realistic
    private var demoBrickPile: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Surface / table
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.18), Color(white: 0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Scattered bricks — positioned to align roughly with the bounding box areas
            Group {
                // Large red 2x4 brick (top-left area)
                demoBrick(width: w * 0.22, height: w * 0.11, color: .red, studsX: 4, studsY: 2)
                    .rotationEffect(.degrees(-8))
                    .position(x: w * 0.22, y: h * 0.25)

                // Green 2x2 plate (top-right area)
                demoBrick(width: w * 0.12, height: w * 0.12, color: .green, studsX: 2, studsY: 2)
                    .rotationEffect(.degrees(5))
                    .position(x: w * 0.62, y: h * 0.20)

                // Orange slope (center area)
                demoSlope(width: w * 0.16, height: w * 0.14, color: .orange)
                    .rotationEffect(.degrees(-3))
                    .position(x: w * 0.42, y: h * 0.62)

                // Blue 1x2 brick (right-center)
                demoBrick(width: w * 0.12, height: w * 0.07, color: .blue, studsX: 2, studsY: 1)
                    .rotationEffect(.degrees(12))
                    .position(x: w * 0.72, y: h * 0.58)

                // Cyan tile (bottom-left)
                demoBrick(width: w * 0.10, height: w * 0.10, color: .cyan, studsX: 1, studsY: 1)
                    .rotationEffect(.degrees(-15))
                    .position(x: w * 0.18, y: h * 0.75)

                // Extra scattered pieces for realism
                demoBrick(width: w * 0.14, height: w * 0.07, color: .yellow, studsX: 2, studsY: 1)
                    .rotationEffect(.degrees(22))
                    .position(x: w * 0.50, y: h * 0.38)

                demoBrick(width: w * 0.10, height: w * 0.10, color: Color(white: 0.35), studsX: 2, studsY: 2)
                    .rotationEffect(.degrees(-6))
                    .position(x: w * 0.82, y: h * 0.32)

                demoBrick(width: w * 0.16, height: w * 0.08, color: .white, studsX: 3, studsY: 1)
                    .rotationEffect(.degrees(10))
                    .position(x: w * 0.30, y: h * 0.45)

                demoBrick(width: w * 0.08, height: w * 0.08, color: .purple, studsX: 1, studsY: 1)
                    .rotationEffect(.degrees(-20))
                    .position(x: w * 0.60, y: h * 0.80)

                demoSlope(width: w * 0.12, height: w * 0.10, color: .red.opacity(0.8))
                    .rotationEffect(.degrees(30))
                    .position(x: w * 0.85, y: h * 0.75)
            }
        }
    }

    /// A single LEGO brick shape with studs
    private func demoBrick(width: CGFloat, height: CGFloat, color: Color, studsX: Int, studsY: Int) -> some View {
        ZStack {
            // Brick body
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: width, height: height)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 2)

            // Darker edge for 3D effect
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width, height: height)

            // Studs grid
            let studSize = min(width / CGFloat(studsX + 1), height / CGFloat(studsY + 1)) * 0.5
            let spacingX = width / CGFloat(studsX + 1)
            let spacingY = height / CGFloat(studsY + 1)

            ForEach(0..<studsY, id: \.self) { row in
                ForEach(0..<studsX, id: \.self) { col in
                    Circle()
                        .fill(color.opacity(0.85))
                        .frame(width: studSize, height: studSize)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 0.5, x: 0, y: 1)
                        .position(
                            x: spacingX * CGFloat(col + 1) - width / 2,
                            y: spacingY * CGFloat(row + 1) - height / 2
                        )
                }
            }
            .frame(width: width, height: height)
        }
    }

    /// A slope brick shape
    private func demoSlope(width: CGFloat, height: CGFloat, color: Color) -> some View {
        ZStack {
            // Slope body — trapezoid approximation
            Path { path in
                path.move(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: 0, y: height * 0.3))
                path.addLine(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: height))
                path.closeSubpath()
            }
            .fill(color)
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 2)

            // Stud on top flat portion
            Circle()
                .fill(color.opacity(0.85))
                .frame(width: width * 0.18, height: width * 0.18)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                }
                .position(x: width * 0.2, y: height * 0.55)
        }
        .frame(width: width, height: height)
    }

    // MARK: - Demo Source Image Generation

    /// Renders the brick pile as a UIImage for use as a source image in piece location snapshots
    @MainActor
    private func generateDemoPileImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let w = size.width
            let h = size.height

            // Dark background
            let bgGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(white: 0.18, alpha: 1).cgColor, UIColor(white: 0.10, alpha: 1).cgColor] as CFArray,
                locations: [0, 1]
            )!
            ctx.cgContext.drawLinearGradient(bgGradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])

            // Draw brick shapes
            let bricks: [(CGRect, UIColor)] = [
                (CGRect(x: w * 0.11, y: h * 0.19, width: w * 0.22, height: w * 0.11), .red),
                (CGRect(x: w * 0.56, y: h * 0.14, width: w * 0.12, height: w * 0.12), .green),
                (CGRect(x: w * 0.34, y: h * 0.55, width: w * 0.16, height: w * 0.14), .orange),
                (CGRect(x: w * 0.66, y: h * 0.52, width: w * 0.12, height: w * 0.07), .blue),
                (CGRect(x: w * 0.12, y: h * 0.68, width: w * 0.10, height: w * 0.10), .cyan),
                (CGRect(x: w * 0.43, y: h * 0.32, width: w * 0.14, height: w * 0.07), .yellow),
                (CGRect(x: w * 0.76, y: h * 0.26, width: w * 0.10, height: w * 0.10), UIColor(white: 0.35, alpha: 1)),
                (CGRect(x: w * 0.22, y: h * 0.41, width: w * 0.16, height: w * 0.08), .white),
                (CGRect(x: w * 0.54, y: h * 0.74, width: w * 0.08, height: w * 0.08), .purple),
                (CGRect(x: w * 0.79, y: h * 0.69, width: w * 0.12, height: w * 0.10), UIColor.red.withAlphaComponent(0.8)),
            ]

            for (rect, color) in bricks {
                // Brick body with shadow
                ctx.cgContext.saveGState()
                ctx.cgContext.setShadow(offset: CGSize(width: 1, height: 2), blur: 3, color: UIColor.black.withAlphaComponent(0.5).cgColor)
                ctx.cgContext.setFillColor(color.cgColor)
                let brickPath = UIBezierPath(roundedRect: rect, cornerRadius: 2)
                brickPath.fill()
                ctx.cgContext.restoreGState()

                // Studs (2x2 grid per brick)
                let studSize = min(rect.width, rect.height) * 0.18
                for row in 0..<2 {
                    for col in 0..<2 {
                        let cx = rect.minX + rect.width * CGFloat(col + 1) / 3.0
                        let cy = rect.minY + rect.height * CGFloat(row + 1) / 3.0
                        let studRect = CGRect(x: cx - studSize / 2, y: cy - studSize / 2, width: studSize, height: studSize)
                        ctx.cgContext.setFillColor(color.withAlphaComponent(0.85).cgColor)
                        ctx.cgContext.fillEllipse(in: studRect)
                        ctx.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
                        ctx.cgContext.setLineWidth(0.5)
                        ctx.cgContext.strokeEllipse(in: studRect)
                    }
                }
            }
        }
    }

    // MARK: - Animation Logic

    private func startPhase1Animation() {
        let demoBoxes: [(CGRect, String, Color)] = [
            (CGRect(x: 0.1, y: 0.15, width: 0.25, height: 0.2), "Brick 2x4", .red),
            (CGRect(x: 0.55, y: 0.1, width: 0.2, height: 0.18), "Plate 2x2", .green),
            (CGRect(x: 0.3, y: 0.55, width: 0.22, height: 0.2), "Slope 45°", .orange),
            (CGRect(x: 0.65, y: 0.5, width: 0.18, height: 0.22), "Brick 1x2", .blue),
            (CGRect(x: 0.1, y: 0.65, width: 0.2, height: 0.15), "Tile 1x1", .cyan),
        ]

        phaseExplanation = "The camera scans for LEGO bricks in real time..."

        for (index, (rect, label, color)) in demoBoxes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.8) {
                let box = DemoBox(rect: rect, label: label, color: color, opacity: 0)
                animatedBoxes.append(box)
                if let lastIndex = animatedBoxes.indices.last {
                    withAnimation(.easeIn(duration: 0.4)) {
                        animatedBoxes[lastIndex].opacity = 1.0
                    }
                }

                if index == 1 {
                    phaseExplanation = "Bounding boxes appear as pieces are detected — but nothing is recorded yet."
                }
                if index == 3 {
                    phaseExplanation = "When you see the pieces highlighted, you're ready to capture!"
                }
            }
        }
    }

    private func startPhase2Animation() {
        phaseExplanation = "Tap the capture button to identify pieces..."

        // Generate a source image from the brick pile for piece location snapshots
        let sourceImage = generateDemoPileImage(size: CGSize(width: 800, height: 600))
        let captureIdx = session.recordSourceImage(sourceImage)

        // Bounding boxes for each demo piece (normalized 0-1 coordinates matching brick positions)
        let demoBoundingBoxes: [CGRect] = [
            CGRect(x: 0.11, y: 0.19, width: 0.22, height: 0.12),  // Brick 2x4 red
            CGRect(x: 0.56, y: 0.14, width: 0.12, height: 0.12),  // Brick 2x2 blue (near green plate position)
            CGRect(x: 0.43, y: 0.32, width: 0.14, height: 0.08),  // Brick 1x2 yellow
            CGRect(x: 0.22, y: 0.39, width: 0.16, height: 0.08),  // Brick 1x4 green (near white brick)
            CGRect(x: 0.76, y: 0.26, width: 0.10, height: 0.10),  // Brick 1x1 black (near gray brick)
            CGRect(x: 0.11, y: 0.19, width: 0.22, height: 0.12),  // Plate 2x4 red (same area as red brick)
            CGRect(x: 0.56, y: 0.14, width: 0.12, height: 0.12),  // Plate 2x2 green
            CGRect(x: 0.54, y: 0.74, width: 0.08, height: 0.08),  // Tile 2x2 black (near purple)
            CGRect(x: 0.34, y: 0.55, width: 0.16, height: 0.14),  // Slope 45° red (orange slope area)
            CGRect(x: 0.12, y: 0.68, width: 0.10, height: 0.10),  // Wheel black (near cyan tile)
        ]

        let demoPieces: [(String, String, PieceCategory, LegoColor, Int, Int, Int, Int)] = [
            ("3001", "Brick 2x4", .brick, .red, 2, 4, 3, 8),
            ("3003", "Brick 2x2", .brick, .blue, 2, 2, 3, 12),
            ("3004", "Brick 1x2", .brick, .yellow, 1, 2, 3, 10),
            ("3010", "Brick 1x4", .brick, .green, 1, 4, 3, 6),
            ("3005", "Brick 1x1", .brick, .black, 1, 1, 3, 8),
            ("3020", "Plate 2x4", .plate, .red, 2, 4, 1, 6),
            ("3022", "Plate 2x2", .plate, .green, 2, 2, 1, 8),
            ("3068", "Tile 2x2", .tile, .black, 2, 2, 1, 4),
            ("3039", "Slope 45° 2x2", .slope, .red, 2, 2, 3, 6),
            ("4624", "Wheel Small", .wheel, .black, 1, 1, 3, 4),
        ]

        // Simulate 3 capture taps
        let captureGroups = [
            Array(demoPieces[0..<4]),
            Array(demoPieces[4..<7]),
            Array(demoPieces[7..<10])
        ]

        for (groupIndex, group) in captureGroups.enumerated() {
            let delay = Double(groupIndex) * 2.5 + 0.5

            // Flash
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeIn(duration: 0.1)) { showCaptureFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 0.2)) { showCaptureFlash = false }
                }
                phaseExplanation = "Capture \(groupIndex + 1) of 3 — analyzing pieces..."
            }

            // Add pieces
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.8) {
                for (pieceIndex, (partNum, name, cat, color, w, l, h, qty)) in group.enumerated() {
                    // Find the global index for this piece's bounding box
                    let globalIndex = captureGroups[0..<groupIndex].reduce(0) { $0 + $1.count } + pieceIndex
                    let bbox = globalIndex < demoBoundingBoxes.count ? demoBoundingBoxes[globalIndex] : nil
                    let piece = LegoPiece(
                        partNumber: partNum,
                        name: name,
                        category: cat,
                        color: color,
                        dimensions: PieceDimensions(studsWide: w, studsLong: l, heightUnits: h),
                        confidence: Double.random(in: 0.7...0.98),
                        quantity: qty,
                        boundingBox: bbox,
                        captureIndex: captureIdx
                    )
                    session.pieces.append(piece)
                    session.totalPiecesFound += qty
                    withAnimation(.easeInOut(duration: 0.3)) {
                        capturedPieceNames.append("\(name) (\(color.rawValue)) x\(qty)")
                    }
                }
                let totalAdded = group.reduce(0) { $0 + $1.7 }
                phaseExplanation = "+\(totalAdded) pieces added to inventory"
            }
        }

        // Done
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            withAnimation { demoPhase = .done }
        }
    }
}
