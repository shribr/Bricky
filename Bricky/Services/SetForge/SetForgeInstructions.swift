import Foundation

/// Builds layer-by-layer assembly instructions from a Set Forge brick list,
/// producing the app's shared `BuildStep` model so forged sets reuse the
/// existing instructions UI.
///
/// Strategy: one step per build layer (bottom→top). When a layer contains more
/// than `maxBricksPerStep` bricks it is split into numbered sub-steps so no
/// single step is overwhelming (the "brick-count-based" strategy from
/// `INSTRUCTIONS_GENERATOR.md`).
enum SetForgeInstructions {

    /// Max bricks introduced in a single step. Kept modest so forged/scanned
    /// sets read as followable instructions, not a wall of pieces per layer.
    static let maxBricksPerStep = 20

    /// The bricks placed in each step, in the same order as `steps(for:)`.
    /// Element `i` holds exactly the bricks introduced by `steps(for:)[i]`, so
    /// the two arrays are index-aligned for the per-step 3D preview.
    static func stepGroups(for bricks: [PlacedBrick]) -> [[PlacedBrick]] {
        guard !bricks.isEmpty else { return [] }

        let ordered = SetForgeLDRExporter.sorted(bricks)
        var byLayer: [Int: [PlacedBrick]] = [:]
        for b in ordered { byLayer[b.y, default: []].append(b) }
        let layers = byLayer.keys.sorted()

        var groups: [[PlacedBrick]] = []
        for y in layers {
            let layerBricks = byLayer[y] ?? []
            let chunks = stride(from: 0, to: layerBricks.count, by: maxBricksPerStep).map {
                Array(layerBricks[$0..<min($0 + maxBricksPerStep, layerBricks.count)])
            }
            groups.append(contentsOf: chunks)
        }
        return groups
    }

    static func steps(for bricks: [PlacedBrick]) -> [BuildStep] {
        guard !bricks.isEmpty else { return [] }

        let ordered = SetForgeLDRExporter.sorted(bricks)
        // Group by build layer.
        var byLayer: [Int: [PlacedBrick]] = [:]
        for b in ordered { byLayer[b.y, default: []].append(b) }
        let layers = byLayer.keys.sorted()

        var steps: [BuildStep] = []
        var stepNumber = 1

        for (layerIndex, y) in layers.enumerated() {
            let layerBricks = byLayer[y] ?? []
            let chunks = stride(from: 0, to: layerBricks.count, by: maxBricksPerStep).map {
                Array(layerBricks[$0..<min($0 + maxBricksPerStep, layerBricks.count)])
            }

            for (chunkIndex, chunk) in chunks.enumerated() {
                let pieceSummary = summarize(chunk)
                let layerLabel = "Layer \(layerIndex + 1) of \(layers.count)"
                let instruction: String
                if chunks.count > 1 {
                    instruction = "\(layerLabel), part \(chunkIndex + 1) of \(chunks.count): "
                        + "place \(chunk.count) bricks to continue this layer."
                } else if layerIndex == 0 {
                    instruction = "Start the base: build \(layerLabel.lowercased()) flat on your table, "
                        + "matching the colours shown."
                } else {
                    instruction = "\(layerLabel): press \(chunk.count) bricks onto the studs of the layer below, "
                        + "keeping seams offset from the previous layer for strength."
                }

                let tip = (layerIndex > 0 && chunkIndex == 0)
                    ? "Stagger bricks over the seams beneath them so the model locks together."
                    : nil

                steps.append(BuildStep(
                    stepNumber: stepNumber,
                    instruction: instruction,
                    piecesUsed: pieceSummary,
                    tip: tip
                ))
                stepNumber += 1
            }
        }
        return steps
    }

    /// Compact "3× Red 1×4 Brick, 2× White 1×2 Brick" summary for a step.
    private static func summarize(_ bricks: [PlacedBrick]) -> String {
        var counts: [String: (color: LegoColor, length: Int, qty: Int)] = [:]
        for b in bricks {
            let key = "\(b.length)-\(b.color.rawValue)"
            if var e = counts[key] { e.qty += 1; counts[key] = e }
            else { counts[key] = (b.color, b.length, 1) }
        }
        let parts = counts.values
            .sorted { $0.qty != $1.qty ? $0.qty > $1.qty : $0.length > $1.length }
            .map { "\($0.qty)× \($0.color.rawValue) \(SetForgeContract.name(forLength: $0.length))" }
        return parts.joined(separator: ", ")
    }
}
