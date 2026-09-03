import Vision
import UIKit
import CoreML
import CoreImage

/// Brick recognition service using on-device CoreML via BrickClassificationPipeline.
final class ObjectRecognitionService: ObservableObject {
    @Published var detectedObjects: [DetectedObject] = []
    @Published var isProcessing = false
    @Published var lastAnalysisTime: TimeInterval = 0

    private var frameCount = 0
    private let processEveryNFrames = 5
    private let pipeline = BrickClassificationPipeline()
    private let catalog = LegoPartsCatalog.shared

    struct DetectedObject: Identifiable {
        let id = UUID()
        let label: String
        let confidence: Float
        var boundingBox: CGRect
        let dominantColor: LegoColor
        let estimatedCategory: PieceCategory
        let estimatedDimensions: PieceDimensions
        let partNumber: String
        let source: String // "offline"
        /// Normalized contour points (0-1, Vision coords) tracing the brick perimeter.
        var contourPoints: [CGPoint]?
        /// Separate confidence in the brick's shape vs its color (0–1).
        var shapeConfidence: Float = 0.5
        var colorConfidence: Float = 0.5
    }

    /// Process a video frame from the camera
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        frameCount += 1
        guard frameCount % processEveryNFrames == 0 else { return }

        let startTime = PerformanceMonitor.shared.startTiming()
        let detections = pipeline.analyzeFrame(pixelBuffer)
        PerformanceMonitor.shared.recordRecognitionLatency(startedAt: startTime)
        let objects = detections.map { det in
            DetectedObject(
                label: det.name,
                confidence: det.confidence,
                boundingBox: det.boundingBox,
                dominantColor: det.color,
                estimatedCategory: det.category,
                estimatedDimensions: det.dimensions,
                partNumber: det.partNumber,
                source: "offline",
                contourPoints: det.contourPoints,
                shapeConfidence: det.shapeConfidence,
                colorConfidence: det.colorConfidence
            )
        }

        DispatchQueue.main.async { [weak self] in
            self?.detectedObjects = objects
        }
    }

    /// Process a captured still image with the CoreML pipeline
    func processImage(_ image: UIImage, completion: @escaping ([DetectedObject]) -> Void) {
        DispatchQueue.main.async { self.isProcessing = true }

        let startTime = Date()
        // Snapshot corrections + server consensus up front (immutable value
        // arrays) so the background reranker never reads @Published state off-thread.
        let corrections = BrickCorrectionStore.shared.corrections
        let serverEntries = CorrectionIndexService.shared.entries

        pipeline.detectBricks(in: image) { [weak self] offlineDetections in
            guard let self else { return }

            // Global consensus first, then the user's own local corrections on top.
            let serverApplied = BrickCorrectionReranker.shared.applyServerIndex(
                to: offlineDetections, in: image, using: serverEntries
            )
            let corrected = BrickCorrectionReranker.shared.apply(
                to: serverApplied, in: image, using: corrections
            )

            let objects = corrected.map { det in
                DetectedObject(
                    label: det.name,
                    confidence: det.confidence,
                    boundingBox: det.boundingBox,
                    dominantColor: det.color,
                    estimatedCategory: det.category,
                    estimatedDimensions: det.dimensions,
                    partNumber: det.partNumber,
                    source: "offline",
                    contourPoints: det.contourPoints,
                    shapeConfidence: det.shapeConfidence,
                    colorConfidence: det.colorConfidence
                )
            }

            let elapsed = Date().timeIntervalSince(startTime)
            DispatchQueue.main.async {
                self.detectedObjects = objects
                self.isProcessing = false
                self.lastAnalysisTime = elapsed
                completion(objects)
            }
        }
    }
}
