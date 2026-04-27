import UIKit
import Vision

/// Decides whether a still photo most likely shows a LEGO **minifigure** or a
/// regular **brick / brick pile**, so `PhotoScanView` can route the image
/// into the correct identification pipeline.
///
/// Heuristics (in order of strength):
/// 1. **Face detection** (`VNDetectFaceRectanglesRequest`). Minifigure heads
///    have printed eyes/mouth that the Vision face detector picks up
///    reliably. A confident face hit is a strong "minifigure" signal.
/// 2. **Image classification** (`VNClassifyImageRequest`). The built-in
///    taxonomy returns labels like `figurine`, `doll`, `action_figure`,
///    `block`, `building_block`, `toy_block`, etc. We sum the confidences
///    of labels in each bucket and compare.
///
/// Returns `.ambiguous` when neither signal is decisive — callers should
/// keep whatever the user already selected.
enum PhotoSubjectClassifier {

    enum Subject: String {
        case minifigure
        case brick
        case ambiguous
    }

    /// Runs both Vision passes off the main thread and returns the
    /// best-guess subject for the supplied image.
    static func classify(_ image: UIImage) async -> Subject {
        guard let cgImage = image.cgImage else { return .ambiguous }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = classifySync(cgImage: cgImage)
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Sync core

    private static func classifySync(cgImage: CGImage) -> Subject {
        // Strong signal: any confident face → minifigure.
        if hasConfidentFace(cgImage: cgImage) {
            return .minifigure
        }

        // Otherwise score Vision's image labels.
        let labels = topLabels(cgImage: cgImage, limit: 10)
        return classify(labels: labels)
    }

    // MARK: - Face detection

    private static func hasConfidentFace(cgImage: CGImage) -> Bool {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return false
        }
        guard let faces = request.results, !faces.isEmpty else { return false }
        // VNFaceObservation.confidence is typically 1.0 for solid hits;
        // require at least 0.5 to filter out marginal detections.
        return faces.contains(where: { $0.confidence >= 0.5 })
    }

    // MARK: - Label classification

    /// One scored label returned by `VNClassifyImageRequest`. Pulled out into
    /// its own struct so the scoring rule is unit-testable without running
    /// Vision.
    struct ScoredLabel: Equatable {
        let identifier: String
        let confidence: Float
    }

    private static func topLabels(cgImage: CGImage, limit: Int) -> [ScoredLabel] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        guard let observations = request.results else { return [] }
        return observations
            .filter { $0.confidence >= 0.05 }
            .prefix(limit)
            .map { ScoredLabel(identifier: $0.identifier.lowercased(),
                               confidence: $0.confidence) }
    }

    /// Pure scoring rule. Sum the confidences of labels whose identifier
    /// contains a keyword in each bucket, then pick the higher bucket.
    /// Exposed `internal` for unit tests.
    static func classify(labels: [ScoredLabel]) -> Subject {
        guard !labels.isEmpty else { return .ambiguous }

        var minifigureScore: Float = 0
        var brickScore: Float = 0

        for label in labels {
            let id = label.identifier
            if matches(id, keywords: minifigureKeywords) {
                minifigureScore += label.confidence
            }
            if matches(id, keywords: brickKeywords) {
                brickScore += label.confidence
            }
        }

        // Require a meaningful margin so near-ties resolve to .ambiguous
        // instead of flipping based on noise.
        let margin: Float = 0.15
        if minifigureScore - brickScore >= margin {
            return .minifigure
        }
        if brickScore - minifigureScore >= margin {
            return .brick
        }
        return .ambiguous
    }

    private static func matches(_ identifier: String, keywords: [String]) -> Bool {
        keywords.contains { identifier.contains($0) }
    }

    /// Identifier substrings that suggest the photo shows a minifigure.
    /// Apple's published taxonomy uses snake_case identifiers.
    private static let minifigureKeywords: [String] = [
        "figurine",
        "action_figure",
        "doll",
        "puppet",
        "mascot",
        "statue",
        "sculpture"
    ]

    /// Identifier substrings that suggest the photo shows bricks.
    private static let brickKeywords: [String] = [
        "block",          // matches "toy_block", "building_block"
        "brick",
        "construction_toy",
        "construction_set",
        "puzzle"
    ]
}
