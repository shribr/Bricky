import CoreML
import Vision
import UIKit
import os.log

/// On-device minifigure identification using a Core ML torso classifier.
///
/// The model classifies torso crop images into torso part numbers. Each
/// part number is then resolved to matching minifigure(s) via the catalog's
/// `figures(usingTorsoPart:)` index.
///
/// Usage flow:
///   1. Caller provides a torso UIImage
///   2. This service runs VNCoreMLRequest for top-K predictions
///   3. Each predicted part number → catalog lookup → candidate figures
///   4. Returns `ClassificationResult` with figures + confidence
@MainActor
final class MinifigureClassificationService {
    static let shared = MinifigureClassificationService()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.app.default",
        category: "MinifigureClassificationService"
    )

    // MARK: - Types

    struct ClassificationResult {
        /// Torso part number predicted by the model.
        let torsoPart: String
        /// Confidence of the torso classification (0.0–1.0).
        let confidence: Double
        /// Minifigures that use this torso part.
        let figures: [Minifigure]
    }

    enum ClassificationError: LocalizedError {
        case modelNotLoaded
        case noResults
        case visionFailed(Error)
        case imageConversionFailed

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Core ML model not available. Falling back to cloud."
            case .noResults:
                return "Model did not return any predictions."
            case .visionFailed(let e):
                return "Vision framework error: \(e.localizedDescription)"
            case .imageConversionFailed:
                return "Failed to convert image for classification."
            }
        }
    }

    // MARK: - State

    /// Whether the Core ML model is ready for inference.
    private(set) var isModelLoaded = false
    private var vnModel: VNCoreMLModel?

    /// The minimum confidence threshold for accepting a Core ML prediction
    /// before falling back to Azure. Configurable for A/B testing.
    var confidenceThreshold: Double = 0.70

    /// Maximum number of top predictions to return.
    var topK: Int = 5

    private init() {}

    // MARK: - Model Loading

    /// Load the Core ML model. Call once at app launch or first use.
    /// Safe to call multiple times — only loads once.
    ///
    /// The model is loaded dynamically by file name so the app compiles
    /// even before the `.mlpackage` is trained and added to the project.
    func loadModel() async {
        guard !isModelLoaded else { return }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all  // Use Neural Engine when available

            let model = try await Task.detached(priority: .userInitiated) {
                // Look for the compiled .mlmodelc in the app bundle.
                // Xcode compiles .mlpackage → .mlmodelc at build time.
                guard let url = Bundle.main.url(
                    forResource: "MinifigureTorsoClassifier",
                    withExtension: "mlmodelc"
                ) else {
                    throw ClassificationError.modelNotLoaded
                }
                return try MLModel(contentsOf: url, configuration: config)
            }.value

            let vn = try VNCoreMLModel(for: model)
            self.vnModel = vn
            self.isModelLoaded = true
            Self.logger.info("Core ML model loaded successfully")
        } catch {
            Self.logger.error("Failed to load Core ML model: \(error.localizedDescription)")
            // Not a fatal error — the app falls back to Azure
        }
    }

    // MARK: - Classification

    /// Classify a torso image and resolve to minifigure candidates.
    ///
    /// Returns up to `topK` results sorted by confidence. Each result maps
    /// a predicted torso part number to the minifigures that use it.
    ///
    /// - Parameter torsoImage: A UIImage of the minifigure torso region.
    /// - Returns: Array of classification results with resolved figures.
    /// - Throws: `ClassificationError` if classification fails.
    func classify(torsoImage: UIImage) async throws -> [ClassificationResult] {
        guard let vnModel else {
            throw ClassificationError.modelNotLoaded
        }

        guard let cgImage = torsoImage.cgImage else {
            throw ClassificationError.imageConversionFailed
        }

        // Run Vision request on a background thread
        let observations = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[VNClassificationObservation], Error>) in

            let request = VNCoreMLRequest(model: vnModel) { request, error in
                if let error {
                    continuation.resume(throwing: ClassificationError.visionFailed(error))
                    return
                }
                let results = request.results as? [VNClassificationObservation] ?? []
                continuation.resume(returning: results)
            }

            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: ClassificationError.visionFailed(error))
            }
        }

        if observations.isEmpty {
            throw ClassificationError.noResults
        }

        // Take top K predictions and resolve each to catalog figures
        let catalog = MinifigureCatalog.shared
        await catalog.load()

        var results: [ClassificationResult] = []

        for obs in observations.prefix(topK) {
            let partNumber = obs.identifier
            let confidence = Double(obs.confidence)

            let figures = catalog.figures(usingTorsoPart: partNumber)

            // Only include results that actually map to catalog figures
            if !figures.isEmpty {
                results.append(ClassificationResult(
                    torsoPart: partNumber,
                    confidence: confidence,
                    figures: figures
                ))
            }
        }

        Self.logger.debug(
            "Classification returned \(results.count) results from \(observations.count) predictions"
        )

        return results
    }

    /// Quick check: does the top prediction meet the confidence threshold?
    /// Used by the identification service to decide whether to skip Azure.
    func classifyWithThreshold(torsoImage: UIImage) async -> [ClassificationResult]? {
        guard isModelLoaded else { return nil }

        do {
            let results = try await classify(torsoImage: torsoImage)
            guard let top = results.first, top.confidence >= confidenceThreshold else {
                Self.logger.info(
                    "Core ML confidence below threshold (\(results.first?.confidence ?? 0) < \(self.confidenceThreshold)), suggesting Azure fallback"
                )
                return nil
            }
            return results
        } catch {
            Self.logger.warning("Core ML classification failed: \(error.localizedDescription)")
            return nil
        }
    }
}
