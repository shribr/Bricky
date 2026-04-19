import SwiftUI

/// Main camera scanning view with live preview and controls
struct CameraScanView: View {
    @StateObject private var viewModel = CameraViewModel()
    @StateObject private var inventoryStore = InventoryStore.shared
    @StateObject private var environmentMonitor = EnvironmentMonitor.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var scanSettings = ScanSettings.shared
    @ObservedObject private var subscription = SubscriptionManager.shared
    @State private var showingManualAdd = false
    @State private var flashOn = false
    @State private var navigateToResults = false
    @State private var showModePicker = false
    @State private var showSaveOptions = false
    @State private var showMergeSheet = false
    @State private var showStopConfirmation = false
    @State private var showScanGuide = false
    @State private var captureFlash = false
    @State private var lastCaptureCount: Int?
    @State private var pieceFoundNotification: String?
    @State private var previousPieceCount: Int = 0
    @State private var showGeneratingResults = false
    @State private var showPaywall = false
    @State private var showTrackingModeHint = false
    /// Tracks whether the view was actively scanning before navigating away
    @State private var wasScanningBeforeNav = false
    /// Sprint 6 / A2 — popcorn auto-stop suggestion banner.
    @StateObject private var autoStopMonitor = ScanAutoStopMonitor()
    /// Sprint C — geolocation. Shown once on the user's first scan when
    /// they haven't yet decided about location tagging.
    @State private var showLocationConsent = false

    var body: some View {
        ZStack {
            // Camera Preview — switches between AR and standard
            if viewModel.isARMode {
                ARCameraPreview(session: viewModel.arCameraManager.session)
                    .ignoresSafeArea()
            } else {
                CameraPreview(session: viewModel.cameraManager.session)
                    .ignoresSafeArea()
            }

            // Live detection bounding boxes (hidden in "None" overlay mode)
            if viewModel.isScanning && !viewModel.liveDetections.isEmpty && themeManager.scanOverlayStyle != .none {
                LiveDetectionOverlayView(detections: viewModel.liveDetections)
                    .ignoresSafeArea()
            }

            // Scan coverage heatmap — red→green per cell, clipped to the
            // detected pile boundary so the user can see exactly where to
            // point next. Shown for both regular and detailed modes.
            if viewModel.isScanning {
                if viewModel.isARMode && ARCameraManager.supportsSceneDepth {
                    // LiDAR-fed perspective wireframe — drapes over the
                    // real bricks using scene depth.
                    PileTopographicView(
                        geometry: viewModel.scanCoordinator.geometry,
                        cameraManager: viewModel.arCameraManager
                    )
                } else {
                    ScanCoverageOverlayView(
                        tracker: viewModel.coverageTracker,
                        pileContour: viewModel.scanCoordinator.geometry.snapshot.contour
                    )
                    .ignoresSafeArea()
                }
            }

            // AR tracking quality banner
            if viewModel.isARMode && viewModel.isScanning {
                arTrackingBanner
            }

            // Overlay
            VStack {
                // Top status bar
                topBar

                // Lighting warning
                if let suggestion = environmentMonitor.assessment.suggestion {
                    HStack(spacing: 8) {
                        Image(systemName: environmentMonitor.assessment.lighting == .tooDark || environmentMonitor.assessment.lighting == .dark
                              ? "sun.min.fill" : "sun.max.fill")
                            .foregroundStyle(.yellow)
                        Text(suggestion)
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.7))
                    .clipShape(Capsule())
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut, value: environmentMonitor.assessment)
                }

                Spacer()

                // Detection overlay
                if viewModel.isScanning {
                    scanningOverlay
                }

                Spacer()

                // First-use scan tip
                if !viewModel.isScanning {
                    FeatureTipView(
                        tip: .firstScan,
                        icon: "camera.viewfinder",
                        title: "Ready to Scan",
                        message: "Spread your LEGO pieces on a flat surface with good lighting. Tap the blue button to start the live preview, then capture to identify pieces.",
                        color: Color.legoRed
                    )
                    .padding(.horizontal, 16)
                }

                // Bottom controls
                bottomControls
            }

            // Error overlay
            if let error = viewModel.cameraManager.error {
                errorOverlay(error)
            }

            // Processing Results overlay (pre-rendering highlights)
            if viewModel.isProcessingResults {
                processingResultsOverlay
            }

            // Generating Results animation (shown briefly after stopping scan)
            if showGeneratingResults {
                generatingResultsOverlay
            }

            // Detailed scan: boundary confirmation buttons
            if viewModel.scanPhase == .detectingBoundary
                && viewModel.scanCoordinator.geometry.hasBoundary {
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Text("Confirm Scan Area")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("The orange outline traces your brick pile. Confirm to begin scanning, or rescan to redraw it.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        HStack(spacing: 20) {
                            Button("Rescan") {
                                viewModel.restartBoundary()
                                viewModel.statusMessage = "Slowly sweep camera over your brick pile…"
                            }
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24).padding(.vertical, 10)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())

                            Button("Confirm") {
                                viewModel.confirmBoundary()
                                viewModel.statusMessage = "Scanning…"
                            }
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32).padding(.vertical, 10)
                            .background(Color.blue)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 32)
                    .padding(.bottom, 120)
                }
            }

            // Detailed scan: completion modal with "View Results"
            if viewModel.scanPhase == .complete {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)

                    DetailedScanCompleteView(
                        totalPieces: viewModel.scanSession.totalPiecesFound,
                        uniquePieces: viewModel.scanSession.uniquePieceCount
                    ) {
                        viewModel.stopScanning()
                        navigateToResults = true
                    }
                }
            }
        }
        .onAppear {
            viewModel.setupCamera()
            // Resume camera if we were scanning before navigating away (e.g. back from results)
            if wasScanningBeforeNav {
                wasScanningBeforeNav = false
                viewModel.resumeCamera()
            }
        }
        .onDisappear {
            // Pause the camera session but don't reset scan state — user may come back
            if viewModel.isScanning {
                wasScanningBeforeNav = true
                viewModel.cameraManager.stopSession()
            }
        }
        .navigationDestination(isPresented: $navigateToResults) {
            ScanResultsView(session: viewModel.scanSession)
        }
        .sheet(isPresented: $showingManualAdd) {
            ManualAddPieceView(session: viewModel.scanSession)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .confirmationDialog("Save Inventory", isPresented: $showSaveOptions) {
            Button("Save as New Inventory") {
                viewModel.saveToInventory()
                viewModel.resetSession()
            }
            if !inventoryStore.inventories.isEmpty {
                Button("Add to Existing Inventory") {
                    showMergeSheet = true
                }
            }
            Button("Discard & Reset", role: .destructive) {
                viewModel.resetSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(viewModel.scanSession.totalPiecesFound) pieces scanned")
        }
        .sheet(isPresented: $showMergeSheet) {
            MergeInventorySheet(
                inventories: inventoryStore.inventories,
                scanPieces: viewModel.scanSession.pieces,
                pieceCount: viewModel.scanSession.totalPiecesFound
            ) { selectedId, mode in
                switch mode {
                case .merge:
                    viewModel.mergeIntoInventory(id: selectedId)
                case .replace:
                    viewModel.replaceInventory(id: selectedId)
                }
                viewModel.resetSession()
            }
        }
        .confirmationDialog(
            "Stop Scanning?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Scanning", role: .destructive) {
                viewModel.stopScanning()
                // Show generating results animation then auto-navigate
                if viewModel.scanSession.totalPiecesFound > 0 {
                    withAnimation { showGeneratingResults = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { showGeneratingResults = false }
                        navigateToResults = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = viewModel.scanSession.totalPiecesFound
            if count > 0 {
                Text("This will end scanning and show your \(count) detected pieces.")
            } else {
                Text("This will end the live preview and camera feed. No pieces have been captured yet. You can start a new scan at any time.")
            }
        }
        .sheet(isPresented: $showScanGuide) {
            ScanGuideView()
        }
        .sheet(isPresented: $showLocationConsent) {
            LocationConsentSheet(
                onEnable: {
                    scanSettings.locationCaptureEnabled = true
                    scanSettings.locationConsentPrompted = true
                    Task { _ = await ScanLocationService.shared.requestPermission() }
                },
                onDismiss: {
                    scanSettings.locationConsentPrompted = true
                }
            )
        }
        .onChange(of: viewModel.scanSession.pieces.count) { _, newCount in
            // Sprint 6 / A2 — feed the auto-stop heuristic on every count change.
            autoStopMonitor.observe(pieceCount: newCount)

            guard newCount > previousPieceCount, newCount > 0 else {
                previousPieceCount = newCount
                return
            }
            let latestPiece = viewModel.scanSession.pieces.last
            let name = latestPiece?.name ?? "New piece"
            let color = latestPiece?.color.rawValue ?? ""
            withAnimation(.easeInOut(duration: 0.3)) {
                pieceFoundNotification = "Found: \(name) (\(color))"
            }
            previousPieceCount = newCount
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    pieceFoundNotification = nil
                }
            }
        }
        .onChange(of: viewModel.isScanning) { _, scanning in
            // Reset on every fresh scan; idle ticks don't matter since
            // observe() only fires on count changes.
            if scanning { autoStopMonitor.reset() }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.statusMessage)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    if viewModel.detectionCount > 0 {
                        Text("\(viewModel.scanSession.totalPiecesFound) pieces found")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    // Mode indicator
                    Text(viewModel.analysisMode.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                viewModel.analysisMode == .offline ? Color.white.opacity(0.2) :
                                viewModel.analysisMode == .online ? Color.blue.opacity(0.4) :
                                Color.green.opacity(0.4)
                            )
                        )
                        .foregroundStyle(.white)
                        .onTapGesture { showModePicker = true }

                    // Tracking mode pill (only visible on LiDAR-capable devices).
                    // Shows whether the LiDAR topographic wireframe is active.
                    if ARCameraManager.supportsSceneDepth {
                        trackingModePill
                    }
                }
            }

            Spacer()

            if viewModel.scanSession.totalPiecesFound > 0 {
                Button {
                    navigateToResults = true
                } label: {
                    HStack(spacing: 6) {
                        Text("View Results")
                        Text("\(viewModel.scanSession.totalPiecesFound)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.3))
                            .clipShape(Capsule())
                    }
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .accessibilityHint("Shows scan results with all detected pieces")
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.4), value: viewModel.scanSession.totalPiecesFound)
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.black.opacity(0.85), .black.opacity(0.6), .black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
        .confirmationDialog("Analysis Mode", isPresented: $showModePicker) {
            Button("Offline (Vision)") { viewModel.setAnalysisMode(.offline) }
            if AzureConfiguration.shared.canUseOnlineMode {
                Button("Cloud AI") { viewModel.setAnalysisMode(.online) }
                Button("Hybrid (Recommended)") { viewModel.setAnalysisMode(.hybrid) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose how pieces are identified")
        }
    }

    // MARK: - Scanning Overlay

    private var scanningOverlay: some View {
        VStack(spacing: 16) {
            // Scanning frame
            ZStack {
                // Outer glow pulse
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.legoYellow.opacity(0.3), lineWidth: 6)
                    .frame(width: 286, height: 286)

                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.legoYellow, lineWidth: 2.5)
                    .frame(width: 280, height: 280)

                // Corner brackets
                ZStack {
                    cornerBracket(rotation: 0)
                    cornerBracket(rotation: 90)
                    cornerBracket(rotation: 180)
                    cornerBracket(rotation: 270)
                }

                // Scanning line animation
                ScanLineView()
                    .frame(width: 280, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Detection count badge
            if viewModel.detectionCount > 0 {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "cube.fill")
                            .foregroundStyle(Color.legoYellow)
                        Text("\(viewModel.detectionCount) pieces detected")
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                    ScanCoverageBadge(tracker: viewModel.coverageTracker)
                }
            } else if viewModel.coverageTracker.coveragePercent > 0 {
                ScanCoverageBadge(tracker: viewModel.coverageTracker)
            }

            // Piece-found notification (especially useful in "None" overlay mode)
            if let notification = pieceFoundNotification {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .foregroundStyle(Color.legoYellow)
                    Text(notification)
                        .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Sprint 6 / A2 — popcorn auto-stop suggestion.
            if autoStopMonitor.shouldSuggestStop {
                autoStopBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var autoStopBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Looks like the scanner found everything")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Tap to view results")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
            Button {
                withAnimation { autoStopMonitor.dismissSuggestion() }
                showSaveOptions = true
            } label: {
                Text("View")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
            Button {
                withAnimation { autoStopMonitor.dismissSuggestion() }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(6)
            }
            .accessibilityLabel("Keep scanning")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        .padding(.horizontal, 16)
    }

    private func cornerBracket(rotation: Double) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 20, y: 0))
        }
        .stroke(themeManager.colorTheme.primary, lineWidth: 4)
        .frame(width: 280, height: 280)
        .rotationEffect(.degrees(rotation))
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Progress bar
            if viewModel.scanProgress > 0 {
                VStack(spacing: 4) {
                    ProgressView(value: viewModel.scanProgress)
                        .tint(.legoYellow)
                    Text("Scan progress")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 40)
            }

            // Capture feedback toast
            if let count = lastCaptureCount {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                    Text("+\(count) pieces captured and added to your inventory")
                        .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.green.opacity(0.3))
                .clipShape(Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Main action buttons
            HStack(spacing: 40) {
                // Manual add button
                Button {
                    showingManualAdd = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text("Manual")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Add piece manually")

                // Main capture/scan button
                Button {
                    if viewModel.isScanning {
                        // Optional high-res snapshot for cloud analysis
                        let beforeCount = viewModel.scanSession.totalPiecesFound
                        viewModel.captureAndAnalyze()
                        // Show capture feedback after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            let added = viewModel.scanSession.totalPiecesFound - beforeCount
                            if added > 0 {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    lastCaptureCount = added
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        lastCaptureCount = nil
                                    }
                                }
                            }
                        }
                    } else {
                        // Check free tier scan limit
                        if subscription.canScan {
                            subscription.recordScan()
                            AnalyticsService.shared.track(.scanStarted)
                            // Sprint C: one-time consent prompt for location tagging.
                            if !scanSettings.locationConsentPrompted {
                                showLocationConsent = true
                            }
                            viewModel.startScanning()
                            // Show scan guide on first use
                            if !UserDefaults.standard.bool(forKey: "hasSeenScanGuide") {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    showScanGuide = true
                                }
                                UserDefaults.standard.set(true, forKey: "hasSeenScanGuide")
                            }
                        } else {
                            showPaywall = true
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 72, height: 72)
                        Circle()
                            .fill(viewModel.isScanning ? Color.legoYellow : Color.legoBlue)
                            .frame(width: 64, height: 64)
                        Image(systemName: viewModel.isScanning ? "camera.aperture" : "video.fill")
                            .font(.title2)
                            .foregroundStyle(.white)

                        // Capture flash
                        if captureFlash {
                            Circle()
                                .fill(.white.opacity(0.5))
                                .frame(width: 72, height: 72)
                        }
                    }
                }
                .accessibilityLabel(viewModel.isScanning ? "Take high-res snapshot" : "Start scanning")
                .accessibilityHint(viewModel.isScanning ? "Takes a high-quality photo for cloud analysis. Pieces are already being added automatically." : "Starts live scanning — pieces are added automatically as detected")

                // Help / Save buttons
                if viewModel.isScanning || viewModel.scanSession.totalPiecesFound > 0 {
                    Button {
                        if viewModel.scanSession.totalPiecesFound > 0 {
                            showSaveOptions = true
                        } else {
                            viewModel.resetSession()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: viewModel.scanSession.totalPiecesFound > 0
                                  ? "square.and.arrow.down.fill"
                                  : "arrow.counterclockwise.circle.fill")
                                .font(.title2)
                            Text(viewModel.scanSession.totalPiecesFound > 0 ? "Save" : "Reset")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel(viewModel.scanSession.totalPiecesFound > 0 ? "Save inventory" : "Reset session")
                } else {
                    // Guide button when not scanning
                    Button {
                        showScanGuide = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.title2)
                            Text("Guide")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("Scanning guide")
                }
            }

            // Pause/Stop controls
            if viewModel.isScanning {
                // Detailed mode: phase-specific controls
                if scanSettings.scanMode == .detailed {
                    detailedScanControls
                } else {
                    regularScanControls
                }
            }
        }
        .padding(.bottom, 20)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.7), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Regular Scan Controls

    private var regularScanControls: some View {
        HStack(spacing: 16) {
            Button {
                if viewModel.isPaused {
                    viewModel.resumeScanning()
                } else {
                    viewModel.pauseScanning()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.subheadline)
                    Text(viewModel.isPaused ? "Resume" : "Pause")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.legoBlue.opacity(0.8))
                .clipShape(Capsule())
            }

            Button {
                showStopConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.circle.fill")
                        .font(.subheadline)
                    Text("Stop")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.7))
                .clipShape(Capsule())
            }

            Button {
                showScanGuide = true
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .accessibilityLabel("Scanning guide")
        }
    }

    // MARK: - Detailed Scan Controls

    private var detailedScanControls: some View {
        VStack(spacing: 10) {
            // Contextual guidance text
            detailedScanGuidance

            HStack(spacing: 16) {
                switch viewModel.scanPhase {
                case .detectingBoundary:
                    // Cancel
                    Button {
                        viewModel.stopScanning()
                    } label: {
                        controlPill(icon: "xmark.circle.fill", text: "Cancel",
                                    background: Color.red.opacity(0.7))
                    }

                case .boundaryReady:
                    // No-op buttons during the brief "ready" pulse
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Starting scan…")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                case .scanning:
                    // Done — finalize the scan now
                    Button {
                        viewModel.finishScan()
                    } label: {
                        controlPill(icon: "checkmark.circle.fill", text: "Done",
                                    background: Color.blue, fontWeight: .semibold,
                                    horizontalPadding: 28, verticalPadding: 10)
                    }

                    // Re-anchor: redraw the boundary, keep pieces
                    Button {
                        viewModel.restartBoundary()
                        viewModel.statusMessage = "Slowly sweep camera over your brick pile…"
                    } label: {
                        controlPill(icon: "arrow.triangle.2.circlepath", text: "Rescan Pile",
                                    background: Color.orange.opacity(0.85))
                    }

                    // Stop entire scan
                    Button {
                        showStopConfirmation = true
                    } label: {
                        controlPill(icon: "stop.circle.fill", text: "Stop",
                                    background: Color.red.opacity(0.7))
                    }

                case .complete:
                    EmptyView()

                case .idle:
                    EmptyView()
                }
            }
        }
    }

    /// Reusable pill-shaped capsule button.
    private func controlPill(
        icon: String,
        text: String,
        background: Color,
        fontWeight: Font.Weight = .medium,
        horizontalPadding: CGFloat = 20,
        verticalPadding: CGFloat = 8
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.subheadline)
            Text(text)
        }
        .font(.subheadline)
        .fontWeight(fontWeight)
        .foregroundStyle(.white)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(background)
        .clipShape(Capsule())
    }

    // MARK: - Detailed Scan Guidance

    @ViewBuilder
    private var detailedScanGuidance: some View {
        switch viewModel.scanPhase {
        case .detectingBoundary:
            guidancePill(
                icon: "iphone.and.arrow.forward",
                text: "Hold camera steady and slowly sweep across the pile"
            )
        case .boundaryReady:
            guidancePill(
                icon: "checkmark.seal.fill",
                text: "Pile detected — get ready to scan"
            )
        case .scanning:
            if let countdown = viewModel.autoCompleteCountdown {
                guidancePill(
                    icon: "timer",
                    text: "Scan auto-completing in \(Int(ceil(countdown)))s — tap Done to finish now"
                )
            } else {
                guidancePill(
                    icon: "camera.viewfinder",
                    text: "Slowly orbit the pile to fill in coverage. Tap Done when satisfied."
                )
            }
        case .complete, .idle:
            EmptyView()
        }
    }

    private func guidancePill(icon: String, text: String, color: Color = .white) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color == .red ? color : Color.legoYellow)
            Text(text)
                .font(.caption2)
                .foregroundStyle(color.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    // MARK: - AR Tracking Quality Banner

    /// Tracking-mode pill shown next to the analysis-mode pill in the top bar.
    /// Tapping toggles between AR World Tracking (LiDAR topographic wireframe
    /// active) and 2D Screen-Space (legacy heatmap). Disabled while a scan is
    /// running because switching tracking mode would tear down the camera
    /// session mid-scan.
    private var trackingModePill: some View {
        let isAR = viewModel.scanSettings.trackingMode == .arWorldTracking
        return Text(isAR ? "LiDAR" : "2D")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(isAR ? Color.green.opacity(0.5) : Color.white.opacity(0.2))
            )
            .foregroundStyle(.white)
            .onTapGesture {
                if viewModel.isScanning {
                    showTrackingModeHint = true
                } else {
                    viewModel.scanSettings.trackingMode = isAR ? .screenSpace : .arWorldTracking
                    HapticManager.impact(.light)
                }
            }
            .alert("Stop the current scan first",
                   isPresented: $showTrackingModeHint) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Tracking mode controls the camera session, so it can only be changed between scans.")
            }
    }

    private var arTrackingBanner: some View {
        VStack {
            if viewModel.arCameraManager.trackingState != .normal {
                let (icon, text, color): (String, String, Color) = {
                    switch viewModel.arCameraManager.trackingState {
                    case .notAvailable:
                        return ("exclamationmark.triangle.fill", "AR tracking not available", .red)
                    case .limited:
                        return ("exclamationmark.circle.fill", "Limited tracking — move slowly", .orange)
                    case .normal:
                        return ("checkmark.circle.fill", "Tracking OK", .green)
                    }
                }()

                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(color)
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(color.opacity(0.9))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.top, 60)
            }
            Spacer()
        }
    }

    // MARK: - Error Overlay

    private func errorOverlay(_ error: CameraManager.CameraError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(error.localizedDescription)
                .font(.headline)
                .multilineTextAlignment(.center)

            if case .permissionDenied = error {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(40)
    }

    // MARK: - Processing Results Overlay

    private var generatingResultsOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.legoYellow)
                    .symbolEffect(.pulse)

                Text("Generating Results")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("\(viewModel.scanSession.totalPiecesFound) pieces captured")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(40)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: showGeneratingResults)
    }

    private var processingResultsOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse)

                Text("Processing Results")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("Generating piece location highlights...")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                ProgressView(value: viewModel.processingProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .frame(maxWidth: 220)

                Text("\(Int(viewModel.processingProgress * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(40)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isProcessingResults)
    }
}

// MARK: - Scanning Line Animation

struct ScanLineView: View {
    @State private var offset: CGFloat = -130
    @State private var glowOpacity: Double = 0.3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Glow band behind the line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.legoYellow.opacity(0.15), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 24)
                .offset(y: reduceMotion ? 0 : offset)
                .opacity(reduceMotion ? 0 : glowOpacity)

            // Main scan line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.legoYellow.opacity(0.8), Color.legoYellow, Color.legoYellow.opacity(0.8), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2.5)
                .shadow(color: Color.legoYellow.opacity(0.6), radius: 4, y: 0)
                .offset(y: reduceMotion ? 0 : offset)
                .opacity(reduceMotion ? 0.7 : 1)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                offset = 130
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                glowOpacity = 0.6
            }
        }
    }
}

// MARK: - Manual Add Piece Sheet

struct ManualAddPieceView: View {
    @ObservedObject var session: ScanSession
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: PieceCategory = .brick
    @State private var selectedColor: LegoColor = .red
    @State private var studsWide = 2
    @State private var studsLong = 4
    @State private var quantity = 1

    var body: some View {
        NavigationStack {
            Form {
                Section("Piece Type") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(PieceCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.systemImage)
                                .tag(cat)
                        }
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(LegoColor.allCases, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(Color.legoColor(color))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if selectedColor == color {
                                            Circle()
                                                .strokeBorder(.white, lineWidth: 3)
                                            Image(systemName: "checkmark")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Dimensions") {
                    Stepper("Width: \(studsWide) studs", value: $studsWide, in: 1...12)
                    Stepper("Length: \(studsLong) studs", value: $studsLong, in: 1...16)
                }

                Section("Quantity") {
                    Stepper("\(quantity)", value: $quantity, in: 1...99)
                }
            }
            .navigationTitle("Add Piece Manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let heightUnits = selectedCategory == .plate || selectedCategory == .tile ? 1 : 3
                        let piece = LegoPiece(
                            partNumber: "manual-\(UUID().uuidString.prefix(8))",
                            name: "\(selectedCategory.rawValue) \(studsWide)×\(studsLong)",
                            category: selectedCategory,
                            color: selectedColor,
                            dimensions: PieceDimensions(studsWide: studsWide, studsLong: studsLong, heightUnits: heightUnits),
                            quantity: quantity
                        )
                        for _ in 0..<quantity {
                            session.addPiece(piece)
                        }
                        HapticManager.impact(.light)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Merge Into Existing Inventory Sheet

struct MergeInventorySheet: View {
    /// What to do when adding the new scan into an existing inventory.
    /// - `merge`  → existing pieces stay; new pieces are added (qty incremented for matches).
    /// - `replace` → existing pieces are wiped first; only the new scan is kept.
    enum MergeMode {
        case merge
        case replace
    }

    let inventories: [InventoryStore.Inventory]
    let scanPieces: [LegoPiece]
    let pieceCount: Int
    let onSelect: (UUID, MergeMode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pendingInventoryId: UUID?
    @State private var pendingSimilarity: Int = 0
    @State private var showActionSheet = false

    var body: some View {
        NavigationStack {
            List(inventories) { inventory in
                Button {
                    let similarity = InventoryStore.shared.similarity(ofScanPieces: scanPieces, to: inventory.id)
                    pendingInventoryId = inventory.id
                    pendingSimilarity = Int(similarity * 100)
                    showActionSheet = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(inventory.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("\(inventory.totalPieces) pieces • \(inventory.uniquePieces) unique")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        let sim = InventoryStore.shared.similarity(ofScanPieces: scanPieces, to: inventory.id)
                        if sim >= 0.6 {
                            Text("\(Int(sim * 100))% match")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(sim >= 0.8 ? Color.red.opacity(0.15) : Color.orange.opacity(0.15))
                                .foregroundStyle(sim >= 0.8 ? .red : .orange)
                                .clipShape(Capsule())
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Update Inventory With \(pieceCount) Pieces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                pendingSimilarity >= 80 ? "Possible Duplicate Scan" : "How should we update this inventory?",
                isPresented: $showActionSheet,
                titleVisibility: .visible
            ) {
                Button("Merge — Add to existing pieces") {
                    if let id = pendingInventoryId {
                        onSelect(id, .merge)
                        dismiss()
                    }
                }
                Button("Replace — Use only this scan", role: .destructive) {
                    if let id = pendingInventoryId {
                        onSelect(id, .replace)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingInventoryId = nil
                }
            } message: {
                if pendingSimilarity >= 80 {
                    Text("This scan is \(pendingSimilarity)% similar to the selected inventory — likely the same pile. Replace is recommended to avoid double-counting. Choose Merge if you've added new bricks since the last scan.")
                } else {
                    Text("Merge keeps everything you already had and adds the new pieces (quantities accumulate for matches). Replace wipes the old contents and keeps only this scan.")
                }
            }
        }
    }
}
