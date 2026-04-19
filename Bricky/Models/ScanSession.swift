import Foundation
import UIKit

/// Represents a scanning session with all identified pieces
class ScanSession: ObservableObject, Identifiable {
    let id: UUID
    let startedAt: Date
    @Published var pieces: [LegoPiece]
    @Published var isScanning: Bool
    @Published var scanProgress: Double
    @Published var totalPiecesFound: Int

    /// Optional captured location at scan start. Nil when location capture is
    /// disabled, permission is denied, or the device couldn't get a fix.
    /// Coordinates are rounded to 4 decimals (~11 m precision) by
    /// `ScanLocationService` before being stored.
    @Published var latitude: Double?
    @Published var longitude: Double?
    /// Reverse-geocoded place name (e.g. "Seattle, WA"). Nil if reverse
    /// geocoding failed or hasn't completed yet.
    @Published var placeName: String?
    /// When the location was captured (typically the same instant as scan start).
    @Published var locationCapturedAt: Date?

    /// Source images from each capture, keyed by a capture index.
    /// Used by the composite screenshot system to generate per-piece highlights on demand.
    var sourceImages: [Int: UIImage] = [:]
    /// Pile boundary contour captured at the same moment as each source image,
    /// keyed by capture index. Points are in normalized coordinates (origin
    /// top-left, 0–1) — same space as `PileGeometry.Snapshot.contour`. Empty
    /// array means no boundary was available at capture time (no LiDAR / no
    /// detections yet).
    var pileBoundaries: [Int: [CGPoint]] = [:]
    private var captureIndex: Int = 0

    /// Recently-added bounding boxes with timestamps for temporal cooldown.
    /// Prevents rapid re-additions of the same spatial region.
    /// `depth` is meters from camera when available (used for stacked-brick separation).
    private var recentRegions: [(box: CGRect, time: Date, depth: Float?)] = []
    /// How long a region stays in the cooldown buffer (seconds)
    private let regionCooldown: TimeInterval = 1.5

    /// Record a source image for a capture and return the capture index
    func recordSourceImage(_ image: UIImage) -> Int {
        let index = captureIndex
        sourceImages[index] = image
        captureIndex += 1
        return index
    }

    /// Record a source image plus the live pile boundary contour at capture
    /// time. The contour is used by the "Pile Map" location view to show
    /// where a piece sits within the entire scanned pile area.
    func recordSourceImage(_ image: UIImage, pileBoundary: [CGPoint]) -> Int {
        let index = recordSourceImage(image)
        if !pileBoundary.isEmpty {
            pileBoundaries[index] = pileBoundary
        }
        return index
    }

    /// Get the source image for a piece's capture
    func sourceImage(for piece: LegoPiece) -> UIImage? {
        guard let captureIdx = piece.captureIndex else { return nil }
        return sourceImages[captureIdx]
    }

    /// Get the pile boundary contour captured alongside this piece's source
    /// image. Returns an empty array if no boundary was available.
    func pileBoundary(for piece: LegoPiece) -> [CGPoint] {
        guard let captureIdx = piece.captureIndex else { return [] }
        return pileBoundaries[captureIdx] ?? []
    }

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        pieces: [LegoPiece] = [],
        isScanning: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.pieces = pieces
        self.isScanning = isScanning
        self.scanProgress = 0
        self.totalPiecesFound = 0
    }

    func addPiece(_ piece: LegoPiece) {
        addPiece(piece, depth: nil)
    }

    /// Adds a piece with optional depth (meters from camera) for 3D-aware
    /// deduplication. When depth is supplied, two detections with overlapping
    /// 2D bounding boxes but ≥`depthSeparationMeters` apart are treated as
    /// distinct pieces (e.g. a brick stacked on top of another).
    func addPiece(_ piece: LegoPiece, depth: Float?) {
        // Check spatial cooldown — reject if this region was just added
        if let box = piece.boundingBox, isInCooldown(box, depth: depth) {
            return
        }

        // Check if this exact physical piece was already detected (coordinate overlap)
        // Checks ALL pieces regardless of partNumber/color to catch classification flicker
        if let box = piece.boundingBox, isDuplicateLocation(box, depth: depth) {
            return // Same physical piece — don't double-count
        }

        if let index = pieces.firstIndex(where: {
            $0.partNumber == piece.partNumber && $0.color == piece.color
        }) {
            pieces[index].quantity += 1
            // Track this detection location
            if let box = piece.boundingBox {
                pieces[index].detectionLocations.append(box)
                pieces[index].detectionDepths.append(depth)
                addToCooldown(box, depth: depth)
            }
        } else {
            var newPiece = piece
            if let box = piece.boundingBox {
                newPiece.detectionLocations = [box]
                newPiece.detectionDepths = [depth]
                addToCooldown(box, depth: depth)
            }
            pieces.append(newPiece)
        }
        totalPiecesFound += 1
    }

    /// Distance threshold (meters) for two overlapping 2D detections to be
    /// considered separate physical pieces (e.g. brick-on-brick stacking).
    private let depthSeparationMeters: Float = 0.02

    /// Check if a bounding box overlaps significantly with ANY existing detection
    /// across ALL piece types, preventing double-counts from classification flicker.
    /// When `depth` is supplied, overlapping detections at very different depths
    /// (≥`depthSeparationMeters`) are NOT considered duplicates — supports
    /// stacked bricks where one sits on top of another.
    private func isDuplicateLocation(_ box: CGRect, depth: Float? = nil) -> Bool {
        let boxCenter = CGPoint(x: box.midX, y: box.midY)
        let boxDiag = sqrt(box.width * box.width + box.height * box.height)

        for existing in pieces {
            for (locIdx, existingBox) in existing.detectionLocations.enumerated() {
                // Primary check: IoU overlap
                let iou = intersectionOverUnion(box, existingBox)
                let centroidClose: Bool = {
                    let existingCenter = CGPoint(x: existingBox.midX, y: existingBox.midY)
                    let dx = boxCenter.x - existingCenter.x
                    let dy = boxCenter.y - existingCenter.y
                    let dist = sqrt(dx * dx + dy * dy)
                    let existingDiag = sqrt(existingBox.width * existingBox.width + existingBox.height * existingBox.height)
                    let avgDiag = (boxDiag + existingDiag) / 2
                    return avgDiag > 0 && dist < avgDiag * 0.35
                }()

                let overlapping = (iou > 0.25) || centroidClose
                guard overlapping else { continue }

                // Depth-aware separation: if both detections have depth and
                // they're far apart in Z, they're stacked — not duplicates.
                if let newDepth = depth,
                   let existingDepth = existing.detectionDepths[safe: locIdx] ?? nil,
                   abs(newDepth - existingDepth) >= depthSeparationMeters {
                    continue
                }
                return true
            }
        }
        return false
    }

    /// Check if a region is in the temporal cooldown window
    private func isInCooldown(_ box: CGRect, depth: Float? = nil) -> Bool {
        let now = Date()
        // Prune expired entries
        recentRegions.removeAll { now.timeIntervalSince($0.time) > regionCooldown }

        let boxCenter = CGPoint(x: box.midX, y: box.midY)
        for recent in recentRegions {
            let recentCenter = CGPoint(x: recent.box.midX, y: recent.box.midY)
            let dx = boxCenter.x - recentCenter.x
            let dy = boxCenter.y - recentCenter.y
            let dist = sqrt(dx * dx + dy * dy)
            let diag = sqrt(box.width * box.width + box.height * box.height)
            // If centroid is within 40% of diagonal, it's the same region —
            // unless depths differ enough to indicate a stacked brick.
            if diag > 0 && dist < diag * 0.4 {
                if let newDepth = depth, let oldDepth = recent.depth,
                   abs(newDepth - oldDepth) >= depthSeparationMeters {
                    continue
                }
                return true
            }
        }
        return false
    }

    /// Add a region to the cooldown buffer
    private func addToCooldown(_ box: CGRect, depth: Float? = nil) {
        recentRegions.append((box: box, time: Date(), depth: depth))
    }

    /// Calculate Intersection over Union for two rectangles
    private func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> Double {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = Double(intersection.width * intersection.height)
        let unionArea = Double(a.width * a.height + b.width * b.height) - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    func removePiece(_ piece: LegoPiece) {
        if let index = pieces.firstIndex(where: { $0.id == piece.id }) {
            if pieces[index].quantity > 1 {
                pieces[index].quantity -= 1
            } else {
                pieces.remove(at: index)
            }
            totalPiecesFound = max(0, totalPiecesFound - 1)
        }
    }

    var uniquePieceCount: Int {
        pieces.count
    }

    var categorySummary: [(category: PieceCategory, count: Int)] {
        let grouped = Dictionary(grouping: pieces) { $0.category }
        return grouped.map { (category: $0.key, count: $0.value.reduce(0) { $0 + $1.quantity }) }
            .sorted { $0.count > $1.count }
    }

    var colorSummary: [(color: LegoColor, count: Int)] {
        let grouped = Dictionary(grouping: pieces) { $0.color }
        return grouped.map { (color: $0.key, count: $0.value.reduce(0) { $0 + $1.quantity }) }
            .sorted { $0.count > $1.count }
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    /// Returns the element at `index` if it exists, otherwise nil.
    /// Used for parallel-arrays where one may be shorter than the other.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
