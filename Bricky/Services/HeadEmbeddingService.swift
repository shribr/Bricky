import CoreML
import Foundation
import OSLog
import UIKit
import Vision

/// Runtime entry point for the trained head-region embedding model.
///
/// Parallel to `TorsoEmbeddingService` but operates on the head/helmet
/// band (top 5–35% of the figure image). Used by the identification
/// cascade to boost candidates with matching head prints and by the
/// `HybridFigureAnalyzer` to detect head-swapped figures.
///
/// Graceful no-op (returns `[]`) when artifacts aren't bundled.
final class HeadEmbeddingService {

    static let shared = HeadEmbeddingService()

    private static let logger = Logger(
        subsystem: "com.bricky.app",
        category: "HeadEmbeddingService"
    )

    private let visionModel: VNCoreMLModel?
    let isAvailable: Bool

    private init() {
        let model: VNCoreMLModel?
        if let url = Bundle.main.url(
                forResource: "HeadEncoder",
                withExtension: "mlmodelc",
                subdirectory: "HeadEmbeddings"
            ) ?? Bundle.main.url(forResource: "HeadEncoder", withExtension: "mlmodelc") {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all
                let coreModel = try MLModel(contentsOf: url, configuration: config)
                model = try VNCoreMLModel(for: coreModel)
                Self.logger.info("Loaded HeadEncoder.mlmodelc")
            } catch {
                Self.logger.error("Failed to load HeadEncoder: \(error.localizedDescription)")
                model = nil
            }
        } else {
            Self.logger.info("HeadEncoder.mlmodelc not bundled — feature disabled")
            model = nil
        }
        self.visionModel = model
        self.isAvailable = (model != nil) && HeadEmbeddingIndex.shared.isAvailable
    }

    func nearestFigures(for cgImage: CGImage, topK: Int = 16) async -> [HeadEmbeddingIndex.Hit] {
        guard isAvailable, let visionModel else { return [] }

        let embedding: [Float]? = await Task.detached(priority: .userInitiated) {
            Self.runEncoder(visionModel: visionModel, image: cgImage)
        }.value
        guard let embedding else { return [] }

        return HeadEmbeddingIndex.shared.nearestNeighbors(of: embedding, topK: topK)
    }

    /// Encode a head crop and return the raw embedding vector.
    /// Used by `HybridFigureAnalyzer` for per-region attribution.
    func encode(cgImage: CGImage) async -> [Float]? {
        guard isAvailable, let visionModel else { return nil }
        return await Task.detached(priority: .userInitiated) {
            Self.runEncoder(visionModel: visionModel, image: cgImage)
        }.value
    }

    private static func runEncoder(visionModel: VNCoreMLModel, image: CGImage) -> [Float]? {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Self.logger.error("VNCoreMLRequest failed: \(error.localizedDescription)")
            return nil
        }

        guard let obs = (request.results?.first as? VNCoreMLFeatureValueObservation),
              let array = obs.featureValue.multiArrayValue else {
            return nil
        }

        let count = array.count
        var out = [Float](repeating: 0, count: count)
        let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: count)
        for i in 0..<count { out[i] = ptr[i] }
        return out
    }
}
