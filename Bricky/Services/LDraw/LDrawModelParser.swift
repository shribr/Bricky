import Foundation

/// Parses an LDraw model (`.ldr` / `.mpd`) into an ordered `AssemblyModel`.
///
/// Unlike `LDrawParser` (which reads a single part's *geometry* — triangles and
/// quads), this reads a *model*: type-1 sub-file references placed with a
/// transform + colour, split into build steps by `0 STEP` meta-commands, with
/// multi-model `.mpd` files (`0 FILE`) resolved by inlining sub-models.
///
/// Coordinate mapping (LDraw → our stud grid):
/// - X/Z: 1 stud = 20 LDU.
/// - Y: LDraw Y points *down*; 1 plate = 8 LDU. We flip the sign so "up" is
///   positive and express height in plate units (a brick layer = 3).
/// - Rotation: the vertical-axis (Y) angle is read from the 3×3 matrix and
///   snapped to 0/90/180/270.
///
/// Limitation (Phase 1): a referenced sub-model is flattened into the step of
/// the line that placed it; sub-model-internal `0 STEP` boundaries are not yet
/// expanded (that's a later refinement).
enum LDrawModelParser {

    /// Parse LDraw model text into an assembly. `defaultColor` is used for parts
    /// whose colour code can't be mapped, and as the top-level inherited colour.
    static func parseAssembly(_ content: String, defaultColor: LegoColor = .gray) -> AssemblyModel {
        let resolved = resolvedPlacements(content, defaultColor: defaultColor)
        return AssemblyModel(placements: resolved.map(brickPlacement(from:)))
    }

    /// Parse LDraw model text into mesh placements that preserve each part's real
    /// LDraw transform (for rendering actual part meshes, e.g. imported OMR set
    /// models) rather than snapping to the stud grid.
    static func meshPlacements(_ content: String, defaultColor: LegoColor = .gray) -> [LDrawMeshPlacement] {
        resolvedPlacements(content, defaultColor: defaultColor).map {
            LDrawMeshPlacement(partNumber: $0.partFile, color: $0.color, transform: $0.transform, step: $0.step)
        }
    }

    /// Shared resolution: split MPD sub-models, expand recursively (composing
    /// transforms + colour inheritance), and compact steps to gapless 1…N.
    private static func resolvedPlacements(_ content: String, defaultColor: LegoColor) -> [ResolvedPlacement] {
        let models = splitModels(content)
        let lines: [ModelLine]
        let files: [String: [ModelLine]]
        if let mainName = models.mainName, let mainLines = models.files[mainName] {
            lines = mainLines
            files = models.files
        } else {
            lines = tokenizeModelLines(content)
            files = [:]
        }
        let expanded = expand(
            lines: lines,
            files: files,
            worldTransform: .identity,
            inheritedColor: defaultColor,
            baseStep: 1,
            depth: 0,
            defaultColor: defaultColor
        )
        return compact(expanded)
    }

    // MARK: - Line model

    /// A single meaningful line in a model: a placement or a step boundary.
    private enum ModelLine {
        case place(colorCode: Int, transform: LDrawParser.Transform, fileName: String)
        case stepBreak
    }

    private struct SplitResult {
        var files: [String: [ModelLine]]
        var mainName: String?
    }

    // MARK: - MPD splitting

    private static func splitModels(_ content: String) -> SplitResult {
        var files: [String: [ModelLine]] = [:]
        var mainName: String?
        var current: String?
        var buffer: [ModelLine] = []

        func flush() {
            if let name = current { files[name] = buffer }
            buffer = []
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let typeStr = tokens.first, let type = Int(typeStr) else { continue }

            if type == 0, tokens.count >= 2, tokens[1].uppercased() == "FILE" {
                flush()
                let name = LDrawPartCatalog.normalize(tokens[2...].joined(separator: " "))
                current = name
                if mainName == nil { mainName = name } // first FILE is the main model
                continue
            }
            if type == 0, tokens.count >= 2, tokens[1].uppercased() == "NOFILE" {
                flush(); current = nil; continue
            }
            if let ml = modelLine(type: type, tokens: tokens) {
                buffer.append(ml)
            }
        }
        flush()
        return SplitResult(files: files, mainName: mainName)
    }

    /// Tokenize a model that has no `0 FILE` header into `ModelLine`s.
    private static func tokenizeModelLines(_ content: String) -> [ModelLine] {
        var result: [ModelLine] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let typeStr = tokens.first, let type = Int(typeStr) else { continue }
            if let ml = modelLine(type: type, tokens: tokens) { result.append(ml) }
        }
        return result
    }

    private static func modelLine(type: Int, tokens: [String]) -> ModelLine? {
        switch type {
        case 0:
            if tokens.count >= 2, tokens[1].uppercased() == "STEP" { return .stepBreak }
            return nil
        case 1:
            return subfileLine(tokens)
        default:
            return nil
        }
    }

    /// Parse a type-1 line: `1 <color> x y z a b c d e f g h i <file>`.
    private static func subfileLine(_ tokens: [String]) -> ModelLine? {
        guard tokens.count >= 15,
              let color = Int(tokens[1]),
              let x = Float(tokens[2]), let y = Float(tokens[3]), let z = Float(tokens[4]),
              let a = Float(tokens[5]), let b = Float(tokens[6]), let c = Float(tokens[7]),
              let d = Float(tokens[8]), let e = Float(tokens[9]), let f = Float(tokens[10]),
              let g = Float(tokens[11]), let h = Float(tokens[12]), let i = Float(tokens[13]) else {
            return nil
        }
        var t = LDrawParser.Transform()
        t.x = x; t.y = y; t.z = z
        t.a = a; t.b = b; t.c = c
        t.d = d; t.e = e; t.f = f
        t.g = g; t.h = h; t.i = i
        let fileName = tokens[14...].joined(separator: " ")
        return .place(colorCode: color, transform: t, fileName: fileName)
    }

    // MARK: - Expansion

    /// A resolved leaf-part placement with its composed LDraw transform.
    private struct ResolvedPlacement {
        let color: LegoColor
        let partFile: String
        let transform: LDrawParser.Transform
        let step: Int
    }

    private static let maxDepth = 12

    private static func expand(
        lines: [ModelLine],
        files: [String: [ModelLine]],
        worldTransform: LDrawParser.Transform,
        inheritedColor: LegoColor,
        baseStep: Int,
        depth: Int,
        defaultColor: LegoColor
    ) -> [ResolvedPlacement] {
        guard depth <= maxDepth else { return [] }

        var placements: [ResolvedPlacement] = []
        var step = baseStep

        for line in lines {
            switch line {
            case .stepBreak:
                // Only advance for sub-model expansion at the top level; nested
                // sub-model step breaks are flattened into the placing step.
                if depth == 0 { step += 1 }
            case let .place(colorCode, transform, fileName):
                let world = worldTransform.multiplied(by: transform)
                let color: LegoColor = colorCode == 16
                    ? inheritedColor
                    : (Self.legoColor(forCode: colorCode) ?? defaultColor)
                let key = LDrawPartCatalog.normalize(fileName)

                if let subLines = files[key] {
                    // Sub-model reference — inline it at the current step.
                    placements.append(contentsOf: expand(
                        lines: subLines,
                        files: files,
                        worldTransform: world,
                        inheritedColor: color,
                        baseStep: step,
                        depth: depth + 1,
                        defaultColor: defaultColor
                    ))
                } else {
                    placements.append(ResolvedPlacement(
                        color: color,
                        partFile: LDrawPartCatalog.normalize(fileName),
                        transform: world,
                        step: step
                    ))
                }
            }
        }
        return placements
    }

    private static func brickPlacement(from resolved: ResolvedPlacement) -> BrickPlacement {
        let spec = LDrawPartCatalog.spec(forPartNumber: resolved.partFile)
        return BrickPlacement(
            category: spec?.category ?? .brick,
            dimensions: spec?.dimensions ?? PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3),
            color: resolved.color,
            partNumber: resolved.partFile,
            position: gridPosition(from: resolved.transform),
            rotationDegrees: rotationDegrees(from: resolved.transform),
            step: resolved.step
        )
    }

    // MARK: - Coordinate / rotation mapping

    private static let lduPerStud: Float = 20
    private static let lduPerPlate: Float = 8

    static func gridPosition(from t: LDrawParser.Transform) -> GridPosition {
        GridPosition(
            x: Int((t.x / lduPerStud).rounded()),
            y: Int((-t.y / lduPerPlate).rounded()), // LDraw Y is down; flip to up
            z: Int((t.z / lduPerStud).rounded())
        )
    }

    /// Vertical-axis rotation snapped to 0/90/180/270 degrees.
    static func rotationDegrees(from t: LDrawParser.Transform) -> Int {
        let radians = atan2(t.c, t.a)
        var degrees = Int((radians * 180 / .pi).rounded())
        degrees = ((degrees % 360) + 360) % 360
        // Snap to the nearest right angle.
        let snapped = Int((Double(degrees) / 90).rounded()) * 90
        return snapped % 360
    }

    // MARK: - Colour mapping

    /// Inverse of `SetForgeContract.ldrawCode(for:)`, plus a few common aliases.
    private static let codeToColor: [Int: LegoColor] = {
        var map: [Int: LegoColor] = [:]
        for color in LegoColor.allCases {
            map[SetForgeContract.ldrawCode(for: color)] = color
        }
        // Common modern/alias codes not in the base map.
        map[71] = .gray        // light bluish gray
        map[72] = .darkGray    // dark bluish gray
        map[70] = .brown       // reddish brown
        map[84] = .tan         // medium nougat
        map[10] = .green       // bright green
        map[28] = .tan         // dark tan
        return map
    }()

    static func legoColor(forCode code: Int) -> LegoColor? {
        codeToColor[code]
    }

    // MARK: - Step compaction

    /// Renumber the distinct used steps to a gapless 1…N, preserving order, so
    /// empty/duplicate `0 STEP` markers don't leave holes.
    private static func compact(_ placements: [ResolvedPlacement]) -> [ResolvedPlacement] {
        let usedSteps = Set(placements.map(\.step)).sorted()
        guard !usedSteps.isEmpty else { return placements }
        var remap: [Int: Int] = [:]
        for (index, step) in usedSteps.enumerated() { remap[step] = index + 1 }
        return placements.map {
            ResolvedPlacement(color: $0.color, partFile: $0.partFile,
                              transform: $0.transform, step: remap[$0.step] ?? $0.step)
        }
    }
}

/// A part placement that preserves the real LDraw transform, for rendering
/// actual part meshes (imported OMR set models).
struct LDrawMeshPlacement {
    let partNumber: String
    let color: LegoColor
    let transform: LDrawParser.Transform
    let step: Int
}
