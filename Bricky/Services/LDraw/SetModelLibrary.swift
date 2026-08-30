import Foundation

/// A bundled LDraw set model available for interactive 3D instructions.
struct SetModelEntry: Decodable, Identifiable {
    /// Resource file name, e.g. `setmodel_minibuild.mpd`.
    let file: String
    let name: String
    /// Official set number, when the model represents a real set.
    let setNumber: String?

    var id: String { file }
}

/// Loads bundled LDraw set models (`.mpd`/`.ldr`) listed in
/// `setmodel_manifest.json`, so real models (e.g. LDraw OMR) can be dropped into
/// `Resources/` and shown as interactive 3D instructions — fully offline.
enum SetModelLibrary {

    /// All bundled set models (empty when none are bundled yet).
    static func entries() -> [SetModelEntry] {
        guard let url = Bundle.main.url(forResource: "setmodel_manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([SetModelEntry].self, from: data) else {
            return []
        }
        return list
    }

    /// The raw model text for an entry, or `nil` if the file is missing.
    static func modelText(for entry: SetModelEntry) -> String? {
        let base = (entry.file as NSString).deletingPathExtension
        let ext = (entry.file as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Parts referenced by a bundled model that the LDraw library can't render.
    static func missingParts(for entry: SetModelEntry) -> [String] {
        guard let text = modelText(for: entry) else { return [] }
        return LDrawModelLibrary.missingParts(inModelText: text)
    }
}
