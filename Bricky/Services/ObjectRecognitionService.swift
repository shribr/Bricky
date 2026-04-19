import Vision
import UIKit
import CoreML
import CoreImage

/// Unified brick recognition service: uses BrickClassificationPipeline (offline)
/// and optionally AzureAIService (online) for enhanced accuracy.
final class ObjectRecognitionService: ObservableObject {
    @Published var detectedObjects: [DetectedObject] = []
    @Published var isProcessing = false
    @Published var analysisMode: AnalysisMode = .offline
    @Published var lastAnalysisTime: TimeInterval = 0

    enum AnalysisMode: String {
        case offline = "Offline"
        case online = "Cloud AI"
        case hybrid = "Hybrid"
    }

    private var frameCount = 0
    private let processEveryNFrames = 5
    private let pipeline = BrickClassificationPipeline()
    private let azureService = AzureAIService.shared
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
        let source: String // "offline", "cloud", "hybrid"
    }

    /// Process a video frame from the camera (offline only for speed)
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
                source: "offline"
            )
        }

        DispatchQueue.main.async { [weak self] in
            self?.detectedObjects = objects
        }
    }

    /// Process a captured still image with full pipeline
    func processImage(_ image: UIImage, completion: @escaping ([DetectedObject]) -> Void) {
        DispatchQueue.main.async { self.isProcessing = true }

        let startTime = Date()
        let config = AzureConfiguration.shared
        let useOnline = config.canUseOnlineMode &&
                        (analysisMode == .online || analysisMode == .hybrid)

        // Always run offline pipeline
        pipeline.detectBricks(in: image) { [weak self] offlineDetections in
            guard let self else { return }

            let offlineObjects = offlineDetections.map { det in
                DetectedObject(
                    label: det.name,
                    confidence: det.confidence,
                    boundingBox: det.boundingBox,
                    dominantColor: det.color,
                    estimatedCategory: det.category,
                    estimatedDimensions: det.dimensions,
                    partNumber: det.partNumber,
                    source: "offline"
                )
            }

            if useOnline {
                // Run cloud analysis in parallel
                Task {
                    do {
                        let cloudResponse = try await self.azureService.analyzeImage(image)
                        let cloudObjects = self.convertCloudResults(cloudResponse.bricks)

                        // Merge: prefer cloud results where confidence is higher
                        let merged = self.mergeResults(offline: offlineObjects, cloud: cloudObjects)
                        let elapsed = Date().timeIntervalSince(startTime)

                        await MainActor.run {
                            self.detectedObjects = merged
                            self.isProcessing = false
                            self.lastAnalysisTime = elapsed
                            completion(merged)
                        }
                    } catch {
                        // Cloud failed — use offline results
                        let elapsed = Date().timeIntervalSince(startTime)
                        await MainActor.run {
                            self.detectedObjects = offlineObjects
                            self.isProcessing = false
                            self.lastAnalysisTime = elapsed
                            completion(offlineObjects)
                        }
                    }
                }
            } else {
                let elapsed = Date().timeIntervalSince(startTime)
                DispatchQueue.main.async {
                    self.detectedObjects = offlineObjects
                    self.isProcessing = false
                    self.lastAnalysisTime = elapsed
                    completion(offlineObjects)
                }
            }
        }
    }

    // MARK: - Cloud result conversion

    private func convertCloudResults(_ bricks: [AzureAIService.CloudBrickResult]) -> [DetectedObject] {
        return bricks.map { brick in
            let category = PieceCategory.fromCloudString(brick.category)
            let color = LegoColor(rawValue: brick.color) ?? .gray

            return DetectedObject(
                label: brick.name,
                confidence: brick.confidence,
                boundingBox: .zero, // Cloud doesn't provide bounding boxes
                dominantColor: color,
                estimatedCategory: category,
                estimatedDimensions: PieceDimensions(
                    studsWide: brick.studsWide,
                    studsLong: brick.studsLong,
                    heightUnits: category == .plate || category == .tile ? 1 : 3
                ),
                partNumber: brick.partNumber,
                source: "cloud"
            )
        }
    }

    // MARK: - Result merging

    private func mergeResults(offline: [DetectedObject], cloud: [DetectedObject]) -> [DetectedObject] {
        // Start with cloud results (generally more accurate for identification)
        // but carry over bounding boxes from local detection since cloud doesn't provide them
        var merged: [DetectedObject] = []

        for cloudPiece in cloud {
            // Find matching offline detection to get its bounding box
            let matchingOffline = offline.first { offlinePiece in
                offlinePiece.estimatedCategory == cloudPiece.estimatedCategory &&
                offlinePiece.dominantColor == cloudPiece.dominantColor &&
                abs(offlinePiece.estimatedDimensions.studsWide - cloudPiece.estimatedDimensions.studsWide) <= 1 &&
                abs(offlinePiece.estimatedDimensions.studsLong - cloudPiece.estimatedDimensions.studsLong) <= 1
            }

            if let match = matchingOffline, cloudPiece.boundingBox == .zero {
                // Use cloud identification with local bounding box
                var enriched = cloudPiece
                enriched.boundingBox = match.boundingBox
                merged.append(enriched)
            } else {
                merged.append(cloudPiece)
            }
        }

        // Add offline detections that don't have a cloud counterpart
        for offlinePiece in offline {
            let hasSimilarCloud = cloud.contains { cloudPiece in
                cloudPiece.estimatedCategory == offlinePiece.estimatedCategory &&
                cloudPiece.dominantColor == offlinePiece.dominantColor &&
                abs(cloudPiece.estimatedDimensions.studsWide - offlinePiece.estimatedDimensions.studsWide) <= 1 &&
                abs(cloudPiece.estimatedDimensions.studsLong - offlinePiece.estimatedDimensions.studsLong) <= 1
            }
            if !hasSimilarCloud {
                merged.append(offlinePiece)
            }
        }

        return merged
    }
}
