import Foundation

/// Turns an ordered `AssemblyModel` into human-readable `BuildStep`s. Because
/// the text and piece list are derived from the *same* placements the 3D viewer
/// renders, the instructions always match what's shown (the core fix for
/// "instructions look nothing like the build").
enum BuildStepPlanner {

    static func steps(for model: AssemblyModel) -> [BuildStep] {
        guard model.stepCount > 0 else { return [] }
        let bounds = model.bounds

        var steps: [BuildStep] = []
        for stepNumber in 1...model.stepCount {
            let group = model.placements(inStep: stepNumber)
            guard !group.isEmpty else { continue }

            let summary = summarize(group)
            let instruction: String
            if stepNumber == 1 {
                instruction = "Start the base: place \(summary)."
            } else {
                let hint = positionalHint(for: group, in: bounds)
                instruction = hint.isEmpty ? "Add \(summary)." : "Add \(summary) \(hint)."
            }
            let tip = stepNumber == 1
                ? "Line the pieces up flush so later layers sit squarely on top."
                : nil

            steps.append(BuildStep(
                stepNumber: stepNumber,
                instruction: instruction,
                piecesUsed: summary,
                tip: tip
            ))
        }
        return steps
    }

    // MARK: - Helpers

    /// "2× Red 2×4 Brick, 1× Blue 1×2 Plate" for the pieces added in a step.
    static func summarize(_ placements: [BrickPlacement]) -> String {
        struct Key: Hashable { let color: LegoColor; let label: String }
        var counts: [Key: Int] = [:]
        var order: [Key] = []
        for p in placements {
            let key = Key(color: p.color, label: p.dimensions.displayString)
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        return order
            .map { "\(counts[$0] ?? 0)× \($0.color.rawValue) \($0.label)" }
            .joined(separator: ", ")
    }

    /// A coarse placement hint ("on top", "on the left", "at the back") derived
    /// from where the step's pieces sit within the model's bounds.
    static func positionalHint(for placements: [BrickPlacement], in bounds: GridBounds) -> String {
        guard !placements.isEmpty else { return "" }

        let avgX = Double(placements.map { $0.position.x }.reduce(0, +)) / Double(placements.count)
        let avgY = Double(placements.map { $0.position.y }.reduce(0, +)) / Double(placements.count)
        let avgZ = Double(placements.map { $0.position.z }.reduce(0, +)) / Double(placements.count)

        // If this layer sits clearly above the base, "on top" reads best.
        let ySpan = Double(bounds.max.y - bounds.min.y)
        if ySpan > 0, avgY >= Double(bounds.min.y) + ySpan * 0.5 {
            return "on top"
        }

        // Otherwise pick the axis with the strongest offset from center.
        let xSpan = Double(bounds.max.x - bounds.min.x)
        let zSpan = Double(bounds.max.z - bounds.min.z)
        let xOffset = xSpan > 0 ? (avgX - Double(bounds.min.x)) / xSpan - 0.5 : 0
        let zOffset = zSpan > 0 ? (avgZ - Double(bounds.min.z)) / zSpan - 0.5 : 0

        if abs(xOffset) < 0.2 && abs(zOffset) < 0.2 { return "" }

        if abs(xOffset) >= abs(zOffset) {
            return xOffset < 0 ? "on the left" : "on the right"
        } else {
            return zOffset < 0 ? "at the front" : "at the back"
        }
    }
}
