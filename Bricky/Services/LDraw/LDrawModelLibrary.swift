import Foundation

/// Loads hand-authored LDraw build models bundled in `Resources/` and parses
/// them into `AssemblyModel`s, so select catalog projects render as recognizable
/// shapes (chair, cottage, tower) instead of the procedural fallback.
///
/// Models are authored in the app's stud-grid convention (translation =
/// grid × 20 LDU, plate = 8 LDU, Y up = negative) so `LDrawModelParser` maps
/// them straight onto the same grid the renderer uses.
enum LDrawModelLibrary {
    /// Catalog project name → bundled `.ldr` resource base name.
    static let modelsByProjectName: [String: String] = [
        "Chair": "buildmodel_chair",
        "Cozy Cottage": "buildmodel_cottage",
        "Castle Tower": "buildmodel_tower",
        "Desk": "buildmodel_desk",
        "Pixel Art Heart": "buildmodel_heart",
        "Picture Frame": "buildmodel_frame",
        "Tic Tac Toe Board": "buildmodel_tictactoe",
        "Snowflake Ornament": "buildmodel_snowflake",
        "Pine Tree": "buildmodel_pinetree",
        "Lighthouse": "buildmodel_lighthouse",
        "Skyscraper Tower": "buildmodel_skyscraper",
        "Abstract Tower": "buildmodel_abstracttower",
        "Bridge": "buildmodel_bridge",
        "Mini Desk & Chair": "buildmodel_minideskchair",
    ]

    static func hasModel(forProjectNamed name: String) -> Bool {
        modelsByProjectName[name] != nil
    }

    /// Parse the bundled model for a project, or `nil` if there is none / it is
    /// missing / it parses to nothing.
    static func assembly(forProjectNamed name: String) -> AssemblyModel? {
        guard let resource = modelsByProjectName[name],
              let url = Bundle.main.url(forResource: resource, withExtension: "ldr"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let assembly = LDrawModelParser.parseAssembly(text, defaultColor: .gray)
        return assembly.placements.isEmpty ? nil : assembly
    }
}
