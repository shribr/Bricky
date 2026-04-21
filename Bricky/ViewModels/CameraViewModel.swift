import SwiftUI
import Combine
import ARKit
import os

/// ViewModel for the camera scanning view
@MainActor
final class CameraViewModel: ObservableObject {
    @Published var isScanning = false
    @Published var isPaused = false
    @Published var showResults = false
    @Published var scanProgress: Double = 0
    @Published var statusMessage = "Point camera at your LEGO pieces"
    @Published var detectionCount = 0
    @Published var lastCapturedImage: UIImage?
    @Published var liveDetections: [ObjectRecognitionService.DetectedObject] = []

    /// When set, the scanner enters "find piece" mode — highlighting only this piece type
    @Published var targetPiece: LegoPiece?
    /// Whether the target piece has been found in the current frame
    @Published var targetPieceFound = false

    let cameraManager = CameraManager()
    let arCameraManager = ARCameraManager()
    let recognitionService = ObjectRecognitionService()
    let scanSession = ScanSession()
    let scanSettings = ScanSettings.shared
    let coverageTracker = ScanCoverageTracker()
    /// New unified scan coordinator. Replaces the segment-based
    /// `DetailedScanCoordinator` + `ARDetailedScanCoordinator` pair.
    let scanCoordinator = ContinuousScanCoordinator()

    /// Whether AR world tracking is active
    var isARMode: Bool { scanSettings.trackingMode == .arWorldTracking && ARCameraManager.isSupported }
    /// Whether AR is available on this device
    var arSupported: Bool { ARCameraManager.isSupported }

    private var cancellables = Set<AnyCancellable>()
    private let catalog = LegoPartsCatalog.shared
    private let inventoryStore = InventoryStore.shared
    /// ID of the auto-saved inventory for this session (updated incrementally)
    private var autoSavedInventoryId: UUID?

    /// Whether post-scan processing is in progress (pre-rendering highlights)
    @Published var isProcessingResults = false
    @Published var processingProgress: Double = 0

    // MARK: - Auto-Capture State

    /// Latest frame image for location mapping (updated periodically from camera thread)
    private var latestFrameImage: UIImage?
    /// Tracks which frame image was last recorded to avoid duplicate source images
    private var lastRecordedFrameImage: UIImage?
    /// Thread-safe scan state readable from camera callbacks without hopping to MainActor.
    private let _callbackState = OSAllocatedUnfairLock<CallbackState>(initialState: CallbackState())

    private struct CallbackState: Sendable {
        var isActive = false        // isScanning && !isPaused
        var isAR = false            // isARMode
        var hasFindTarget = false   // targetPiece != nil
        var lastFrameTime: Date = .distantPast
    }

    /// CIContext for converting pixel buffers to UIImages (thread-safe)
    private let frameImageCIContext = CIContext()
    /// Minimum confidence for auto-captured pieces
    private static let autoCaptureMinConfidence: Float = 0.5
    /// How often to snapshot the frame for location mapping
    private static let frameSnapshotInterval: TimeInterval = 0.5
    /// Throttle auto-save to avoid excessive writes
    private var lastAutoSaveTime: Date = .distantPast

    init() {
        scanCoordinator.geometry.arCameraManager = arCameraManager
        setupFrameProcessing()
        syncCallbackState()
    }

    /// Push current scan flags into the lock-protected callback state.
    private func syncCallbackState() {
        let active = isScanning && !isPaused
        let ar = isARMode
        let find = targetPiece != nil
        _callbackState.withLock { s in
            s.isActive = active
            s.isAR = ar
            s.hasFindTarget = find
        }
    }

    func setupCamera() {
        if isARMode {
            arCameraManager.checkPermissions()
        } else {
            cameraManager.checkPermissions()
        }
    }

    func startScanning() {
        isScanning = true
        isPaused = false
        syncCallbackState()
        scanSession.isScanning = true

        // Apply configured coverage detail level
        let detail = ThemeManager.shared.scanCoverageDetail
        coverageTracker.reconfigure(columns: detail.columns, rows: detail.rows)

        scanCoordinator.start()

        if scanSettings.scanMode == .detailed {
            statusMessage = "Slowly sweep camera over your brick pile…"
        } else {
            statusMessage = "Scanning… Hold steady"
        }

        if isARMode {
            arCameraManager.startSession()
        } else {
            cameraManager.startSession()
        }

        // Sprint C: opportunistically tag the scan with location.
        captureLocationIfEnabled()
    }

    /// Sprint C — geolocation. Fire-and-forget single-fix capture so a scan
    /// remembers *where* it happened. Skips silently if the user hasn't
    /// opted in or hasn't granted OS permission.
    private func captureLocationIfEnabled() {
        guard scanSettings.locationCaptureEnabled else { return }
        let service = ScanLocationService.shared
        guard service.authorizationAllowsCapture else { return }
        let session = scanSession
        Task { @MainActor in
            guard let capture = await service.requestCapture() else { return }
            session.latitude = capture.latitude
            session.longitude = capture.longitude
            session.locationCapturedAt = capture.capturedAt
            service.backfillPlaceName(
                for: session.id,
                latitude: capture.latitude,
                longitude: capture.longitude
            )
        }
    }

    func pauseScanning() {
        isPaused = true
        syncCallbackState()
        scanSession.isScanning = false
        statusMessage = "Scan paused"
        if isARMode {
            arCameraManager.stopSession()
        } else {
            cameraManager.stopSession()
        }
    }

    func resumeScanning() {
        isPaused = false
        syncCallbackState()
        scanSession.isScanning = true
        statusMessage = "Scanning... Hold steady"
        if isARMode {
            arCameraManager.startSession()
        } else {
            cameraManager.startSession()
        }
    }

    /// Restart the camera session without resetting scan state.
    /// Used when returning from a pushed view (e.g. results screen).
    func resumeCamera() {
        if isScanning {
            if isARMode {
                arCameraManager.startSession()
            } else {
                cameraManager.startSession()
            }
        }
    }

    func stopScanning() {
        isScanning = false
        isPaused = false
        syncCallbackState()
        scanSession.isScanning = false
        liveDetections = []
        statusMessage = "Scan stopped"

        if isARMode {
            arCameraManager.stopSession()
        } else {
            cameraManager.stopSession()
        }
        scanCoordinator.reset()

        // Save to scan history
        if scanSession.totalPiecesFound > 0 {
            ScanHistoryStore.shared.save(session: scanSession, usedARMode: isARMode)
        }

        // Pre-render highlights in background if configured
        if scanSession.totalPiecesFound > 0 {
            Task { await preRenderAllSnapshots() }
        }
    }

    /// Enter "find piece" mode — camera highlights only the target piece type
    func startFindPiece(_ piece: LegoPiece) {
        targetPiece = piece
        targetPieceFound = false
        isScanning = true
        isPaused = false
        syncCallbackState()
        statusMessage = "Looking for \(piece.name)..."
        cameraManager.startSession()
    }

    /// Exit "find piece" mode
    func stopFindPiece() {
        targetPiece = nil
        targetPieceFound = false
        syncCallbackState()
        stopScanning()
    }

    func captureAndAnalyze() {
        statusMessage = "Analyzing image..."
        HapticManager.impact(.medium)
        cameraManager.capturePhoto()

        // Wait for photo capture then process
        cameraManager.$capturedImage
            .compactMap { $0 }
            .first()
            .sink { [weak self] image in
                self?.processCapture(image)
            }
            .store(in: &cancellables)
    }

    func processCapture(_ image: UIImage) {
        lastCapturedImage = image
        statusMessage = "Identifying pieces..."

        // Record source image for composite mode (one image per capture).
        // Also captures the live pile boundary contour so PieceLocationView
        // can show "where in the pile" the piece sits.
        let captureIdx: Int? = {
            guard scanSettings.locationSnapshotsEnabled else { return nil }
            let boundary = scanCoordinator.geometry.snapshot.contour
            return scanSession.recordSourceImage(image, pileBoundary: boundary)
        }()

        recognitionService.processImage(image) { [weak self] detectedObjects in
            guard let self else { return }

            let snapshotsEnabled = self.scanSettings.locationSnapshotsEnabled
            let useComposite = self.scanSettings.useCompositeMode

            for detected in detectedObjects {
                let match = self.catalog.findBestMatch(
                    category: detected.estimatedCategory,
                    dimensions: detected.estimatedDimensions,
                    color: detected.dominantColor
                )

                let piece = LegoPiece(
                    partNumber: match?.partNumber ?? detected.partNumber,
                    name: match?.name ?? detected.label,
                    category: detected.estimatedCategory,
                    color: detected.dominantColor,
                    dimensions: detected.estimatedDimensions,
                    confidence: Double(detected.confidence),
                    boundingBox: detected.boundingBox,
                    locationSnapshot: nil, // Never render on main thread
                    captureIndex: captureIdx
                )

                self.scanSession.addPiece(piece)
            }

            self.detectionCount = self.scanSession.totalPiecesFound
            let timeStr = String(format: "%.1fs", self.recognitionService.lastAnalysisTime)
            let sourceStr = detectedObjects.first?.source ?? "offline"
            self.statusMessage = "Found \(detectedObjects.count) pieces (\(sourceStr), \(timeStr))"
            self.scanProgress = min(1.0, Double(self.scanSession.totalPiecesFound) / 50.0)

            if self.scanSession.totalPiecesFound > 0 {
                HapticManager.notification(.success)
                self.showResults = true

                // Auto-save on background
                Task.detached(priority: .utility) { [weak self] in
                    await self?.autoSaveSessionBackground()
                }

                // Legacy mode: render snapshots in background (not composite)
                if snapshotsEnabled && !useComposite {
                    Task.detached(priority: .utility) { [weak self] in
                        await self?.renderSnapshotsInBackground(
                            image: image,
                            detectedObjects: detectedObjects
                        )
                    }
                }
            }
        }
    }

    /// Render per-piece snapshots on a background thread (legacy mode)
    private func renderSnapshotsInBackground(
        image: UIImage,
        detectedObjects: [ObjectRecognitionService.DetectedObject]
    ) async {
        let pieces = await MainActor.run { Array(scanSession.pieces) }

        for detected in detectedObjects {
            guard let pieceIndex = pieces.firstIndex(where: {
                $0.partNumber == detected.partNumber ||
                ($0.category == detected.estimatedCategory && $0.color == detected.dominantColor)
            }) else { continue }

            let piece = pieces[pieceIndex]
            guard piece.locationSnapshot == nil, let box = piece.boundingBox else { continue }

            let snapshot = SnapshotRenderer.renderHighlight(
                sourceImage: image,
                highlightBox: box,
                highlightColor: UIColor(Color.legoColor(piece.color))
            )

            await MainActor.run {
                if let idx = self.scanSession.pieces.firstIndex(where: { $0.id == piece.id }) {
                    self.scanSession.pieces[idx].locationSnapshot = snapshot
                }
            }
        }
    }

    /// Pre-render all piece location highlights on a background thread.
    /// Called when scanning stops (if composite mode + pre-render enabled).
    func preRenderAllSnapshots() async {
        guard scanSettings.locationSnapshotsEnabled,
              scanSettings.useCompositeMode,
              scanSettings.preRenderOnComplete else { return }

        let pieces = scanSession.pieces
        let totalToRender = pieces.filter { $0.locationSnapshot == nil && $0.boundingBox != nil }.count
        guard totalToRender > 0 else { return }

        await MainActor.run {
            isProcessingResults = true
            processingProgress = 0
        }

        var rendered = 0
        for piece in pieces {
            guard piece.locationSnapshot == nil,
                  let box = piece.boundingBox,
                  let sourceImage = scanSession.sourceImage(for: piece) else { continue }

            let snapshot = await Task.detached(priority: .userInitiated) {
                SnapshotRenderer.renderHighlight(
                    sourceImage: sourceImage,
                    highlightBox: box,
                    highlightColor: UIColor(Color.legoColor(piece.color))
                )
            }.value

            rendered += 1
            await MainActor.run {
                if let idx = self.scanSession.pieces.firstIndex(where: { $0.id == piece.id }) {
                    self.scanSession.pieces[idx].locationSnapshot = snapshot
                }
                self.processingProgress = Double(rendered) / Double(totalToRender)
            }
        }

        await MainActor.run {
            isProcessingResults = false
            processingProgress = 1.0
        }
    }

    /// Generate a snapshot on demand for a specific piece (composite mode).
    /// Called when user taps "show location" in results.
    func generateSnapshotOnDemand(for piece: LegoPiece) async -> UIImage? {
        guard let box = piece.boundingBox,
              let sourceImage = scanSession.sourceImage(for: piece) else { return nil }

        return await Task.detached(priority: .userInitiated) {
            SnapshotRenderer.renderHighlight(
                sourceImage: sourceImage,
                highlightBox: box,
                highlightColor: UIColor(Color.legoColor(piece.color))
            )
        }.value
    }

    /// Auto-save the current session on a background thread.
    private func autoSaveSessionBackground() async {
        let pieces = await MainActor.run { self.scanSession.pieces }
        let inventoryPieces = pieces.map { piece in
            InventoryStore.InventoryPiece(
                partNumber: piece.partNumber,
                name: piece.name,
                category: piece.category,
                color: piece.color,
                quantity: piece.quantity,
                dimensions: piece.dimensions
            )
        }

        await MainActor.run {
            if let existingId = autoSavedInventoryId {
                inventoryStore.replacePieces(inventoryPieces, in: existingId)
            } else {
                let dateStr = DateFormatter.localizedString(from: scanSession.startedAt, dateStyle: .short, timeStyle: .short)
                let id = inventoryStore.createInventory(name: "Scan \(dateStr)")
                autoSavedInventoryId = id
                inventoryStore.addPieces(inventoryPieces, to: id)
            }
        }
    }

    /// Save current scan session to persistent inventory
    func saveToInventory(name: String? = nil) {
        let inventoryName = name ?? "Scan \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))"
        let invId = inventoryStore.createInventory(name: inventoryName)

        let inventoryPieces = scanSession.pieces.map { piece in
            InventoryStore.InventoryPiece(
                partNumber: piece.partNumber,
                name: piece.name,
                category: piece.category,
                color: piece.color,
                quantity: piece.quantity,
                dimensions: piece.dimensions
            )
        }
        inventoryStore.addPieces(inventoryPieces, to: invId)
        HapticManager.notification(.success)
    }

    /// Merge current scan session into an existing inventory
    func mergeIntoInventory(id: UUID) {
        let inventoryPieces = scanSession.pieces.map { piece in
            InventoryStore.InventoryPiece(
                partNumber: piece.partNumber,
                name: piece.name,
                category: piece.category,
                color: piece.color,
                quantity: piece.quantity,
                dimensions: piece.dimensions
            )
        }
        inventoryStore.addPieces(inventoryPieces, to: id)
        HapticManager.notification(.success)
    }

    /// Replace an existing inventory's contents entirely with the current scan.
    /// Use when the user is re-scanning the same pile and wants the inventory
    /// to reflect the latest state rather than accumulating duplicates.
    func replaceInventory(id: UUID) {
        let inventoryPieces = scanSession.pieces.map { piece in
            InventoryStore.InventoryPiece(
                partNumber: piece.partNumber,
                name: piece.name,
                category: piece.category,
                color: piece.color,
                quantity: piece.quantity,
                dimensions: piece.dimensions
            )
        }
        inventoryStore.replacePieces(inventoryPieces, in: id)
        HapticManager.notification(.success)
    }

    func resetSession() {
        scanSession.pieces.removeAll()
        scanSession.totalPiecesFound = 0
        scanSession.sourceImages.removeAll()
        detectionCount = 0
        scanProgress = 0
        showResults = false
        isProcessingResults = false
        processingProgress = 0
        autoSavedInventoryId = nil
        latestFrameImage = nil
        lastRecordedFrameImage = nil
        lastAutoSaveTime = .distantPast
        coverageTracker.reset()
        scanCoordinator.reset()
        statusMessage = "Point camera at your LEGO pieces"
    }

    private func setupFrameProcessing() {
        // Standard AVCapture frame processing.
        // Runs when scanning is active AND we're either not in AR mode or in
        // "find piece" mode (which always uses the regular camera regardless
        // of the user's tracking-mode setting).
        cameraManager.onFrameCaptured = { [weak self] pixelBuffer in
            guard let self else { return }
            let state = self._callbackState.withLock { $0 }
            guard state.isActive else { return }
            guard !state.isAR || state.hasFindTarget else { return }

            // Periodically snapshot frame as UIImage for auto-capture location mapping
            let shouldSnapshot = self._callbackState.withLock { s -> Bool in
                let now = Date()
                guard now.timeIntervalSince(s.lastFrameTime) >= Self.frameSnapshotInterval else { return false }
                s.lastFrameTime = now
                return true
            }
            if shouldSnapshot {
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                if let cgImage = self.frameImageCIContext.createCGImage(ciImage, from: ciImage.extent) {
                    let image = UIImage(cgImage: cgImage)
                    DispatchQueue.main.async {
                        self.latestFrameImage = image
                    }
                }
            }

            self.recognitionService.processFrame(pixelBuffer)
        }

        // AR frame processing — feeds pixel buffer to Vision and tracks AR state
        arCameraManager.onFrameCaptured = { [weak self] pixelBuffer in
            guard let self else { return }
            let state = self._callbackState.withLock { $0 }
            guard state.isActive, state.isAR else { return }

            // Snapshot frame for location mapping
            let shouldSnapshot = self._callbackState.withLock { s -> Bool in
                let now = Date()
                guard now.timeIntervalSince(s.lastFrameTime) >= Self.frameSnapshotInterval else { return false }
                s.lastFrameTime = now
                return true
            }
            if shouldSnapshot {
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                if let cgImage = self.frameImageCIContext.createCGImage(ciImage, from: ciImage.extent) {
                    let image = UIImage(cgImage: cgImage)
                    DispatchQueue.main.async {
                        self.latestFrameImage = image
                    }
                }
            }

            // Feed to the same Vision pipeline
            self.recognitionService.processFrame(pixelBuffer)
        }

        // AR frame updates — triggers PileGeometryService rebuilds (mesh/depth tiers)
        arCameraManager.onARFrameUpdated = { [weak self] _ in
            guard let self else { return }
            let state = self._callbackState.withLock { $0 }
            guard state.isActive, state.isAR else { return }
            self.scanCoordinator.geometry.onARFrameUpdated()
        }

        // AR tracking state updates removed — ContinuousScanCoordinator does not
        // require per-frame AR tracking quality. Banner UI consumes
        // arCameraManager.trackingState directly.

        recognitionService.$detectedObjects
            .receive(on: DispatchQueue.main)
            .sink { [weak self] objects in
                guard let self, self.isScanning, !self.isPaused else { return }

                // In "find piece" mode, only show the target piece
                if let target = self.targetPiece {
                    let matches = objects.filter { detection in
                        detection.estimatedCategory == target.category &&
                        detection.dominantColor == target.color &&
                        abs(detection.estimatedDimensions.studsWide - target.dimensions.studsWide) <= 1 &&
                        abs(detection.estimatedDimensions.studsLong - target.dimensions.studsLong) <= 1
                    }
                    self.liveDetections = matches
                    self.detectionCount = matches.count
                    let found = !matches.isEmpty
                    if found != self.targetPieceFound {
                        self.targetPieceFound = found
                        if found {
                            HapticManager.notification(.success)
                            self.statusMessage = "Found \(target.name)!"
                        } else {
                            self.statusMessage = "Looking for \(target.name)..."
                        }
                    }
                } else {
                    self.detectionCount = objects.count
                    self.liveDetections = objects

                    // Update coverage map with detected bounding boxes
                    let boxes = objects.map(\.boundingBox)
                    self.coverageTracker.recordDetections(boxes)

                    // Feed the unified scan coordinator (drives geometry + auto-advance)
                    let partNumbers = objects.map(\.partNumber)
                    self.scanCoordinator.recordDetections(
                        boxes: boxes,
                        partNumbers: partNumbers,
                        totalSessionPieces: self.scanSession.pieces.count
                    )

                    // Auto-capture only once we're in the active scanning phase
                    // (or in regular mode where there's no boundary phase)
                    let scanModeAllowsCapture =
                        self.scanSettings.scanMode == .regular ||
                        self.scanCoordinator.phase == .scanning

                    if scanModeAllowsCapture {
                        self.autoCaptureDetections(objects)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Auto-Capture

    /// Automatically adds newly-detected pieces to the scan session in real time.
    /// ScanSession.addPiece handles deduplication via IoU overlap checking.
    private func autoCaptureDetections(_ detections: [ObjectRecognitionService.DetectedObject]) {
        let beforeCount = scanSession.totalPiecesFound

        // Record a source image if we have a fresh frame (avoid re-recording the same frame)
        var captureIdx: Int?
        if let image = latestFrameImage,
           image !== lastRecordedFrameImage,
           scanSettings.locationSnapshotsEnabled {
            captureIdx = scanSession.recordSourceImage(image)
            lastRecordedFrameImage = image
        }

        for detection in detections {
            guard detection.confidence >= Self.autoCaptureMinConfidence else { continue }

            let match = catalog.findBestMatch(
                category: detection.estimatedCategory,
                dimensions: detection.estimatedDimensions,
                color: detection.dominantColor
            )

            let piece = LegoPiece(
                partNumber: match?.partNumber ?? detection.partNumber,
                name: match?.name ?? detection.label,
                category: detection.estimatedCategory,
                color: detection.dominantColor,
                dimensions: detection.estimatedDimensions,
                confidence: Double(detection.confidence),
                boundingBox: detection.boundingBox,
                captureIndex: captureIdx
            )

            // Sample depth at the detection center (LiDAR / sceneDepth devices only).
            let depth: Float? = isARMode ? sampleDepth(for: detection.boundingBox) : nil
            scanSession.addPiece(piece, depth: depth)
        }

        let added = scanSession.totalPiecesFound - beforeCount
        if added > 0 {
            detectionCount = scanSession.totalPiecesFound
            scanProgress = min(1.0, Double(scanSession.totalPiecesFound) / 50.0)
            statusMessage = "\(scanSession.totalPiecesFound) pieces found"
            HapticManager.impact(.light)

            // Throttled auto-save (at most every 5 seconds)
            let now = Date()
            if now.timeIntervalSince(lastAutoSaveTime) >= 5.0 {
                lastAutoSaveTime = now
                Task.detached(priority: .utility) { [weak self] in
                    await self?.autoSaveSessionBackground()
                }
            }
        }
    }

    /// Generate an annotated snapshot of the source image with the detected piece highlighted.
    /// Deprecated — use `SnapshotRenderer.renderHighlight()` on a background thread instead.
    /// Kept for backward compatibility with tests.
    private func generateLocationSnapshot(
        sourceImage: UIImage,
        highlightBox: CGRect,
        color: LegoColor
    ) -> UIImage {
        SnapshotRenderer.renderHighlight(
            sourceImage: sourceImage,
            highlightBox: highlightBox,
            highlightColor: UIColor(Color.legoColor(color))
        )
    }

    /// Sample the per-pixel scene depth at the centre of a Vision-normalized
    /// bounding box. Returns nil if no depth is available (no LiDAR/sceneDepth,
    /// invalid sample, etc).
    private func sampleDepth(for box: CGRect) -> Float? {
        guard let depthData = arCameraManager.latestSceneDepth else { return nil }
        let buffer = depthData.depthMap
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        guard w > 0, h > 0 else { return nil }

        // Vision: origin bottom-left. Camera image: landscape, origin top-left.
        // For portrait viewport the long axis of the depth map maps to screen Y.
        let nx = max(0, min(1, box.midX))
        let ny = max(0, min(1, 1 - box.midY))   // → top-left origin
        let landscapeX = Int(ny * Double(w))
        let landscapeY = Int((1 - nx) * Double(h))
        guard landscapeX >= 0, landscapeX < w, landscapeY >= 0, landscapeY < h else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let row = base.advanced(by: landscapeY * bytesPerRow)
        let depth = row.bindMemory(to: Float32.self, capacity: w)[landscapeX]
        return depth.isFinite && depth > 0.05 && depth < 5.0 ? depth : nil
    }

    // MARK: - Scan Coordinator Pass-Through

    /// Current phase of the new continuous scan coordinator.
    var scanPhase: ContinuousScanCoordinator.Phase { scanCoordinator.phase }

    /// Cumulative pieces detected this session.
    var runningTotalPieces: Int { scanCoordinator.runningTotalPieces }

    /// Cumulative unique part numbers detected this session.
    var runningUniquePieces: Int { scanCoordinator.runningUniquePieces }

    /// 0–1 coverage estimate during the active scanning phase.
    var scanCoverage: Double { scanCoordinator.coverage }

    /// Seconds remaining before auto-completion (nil if not currently counting down).
    var autoCompleteCountdown: Double? { scanCoordinator.autoCompleteCountdown }

    /// User taps "Confirm" on the boundary outline.
    func confirmBoundary() { scanCoordinator.confirmBoundary() }

    /// User taps "Re-scan" — wipes the boundary but keeps detected pieces.
    func restartBoundary() { scanCoordinator.restartBoundary() }

    /// User taps "Done" — finalize the scan now.
    func finishScan() { scanCoordinator.finish() }
}
