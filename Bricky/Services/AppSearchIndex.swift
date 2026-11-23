import Foundation

// MARK: - Categories

/// Result groups shown by app-wide search, in display order.
enum AppSearchCategory: String, CaseIterable, Identifiable {
    case feature, setting, helpArticle, tutorial, tip, buildIdea, set, minifigure, legal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feature: return "Features"
        case .setting: return "Settings"
        case .helpArticle: return "Help Articles"
        case .tutorial: return "Tutorials"
        case .tip: return "Tips"
        case .buildIdea: return "Build Ideas"
        case .set: return "Sets"
        case .minifigure: return "Minifigures"
        case .legal: return "Privacy & Legal"
        }
    }

    var icon: String {
        switch self {
        case .feature: return "sparkles"
        case .setting: return "gearshape.fill"
        case .helpArticle: return "questionmark.circle.fill"
        case .tutorial: return "graduationcap.fill"
        case .tip: return "lightbulb.fill"
        case .buildIdea: return "hammer.fill"
        case .set: return "shippingbox.fill"
        case .minifigure: return "person.fill"
        case .legal: return "hand.raised.fill"
        }
    }

    /// Catalog-backed groups can hold thousands of matches, so they are capped.
    var isCapped: Bool {
        switch self {
        case .buildIdea, .set, .minifigure: return true
        default: return false
        }
    }
}

// MARK: - Destinations

/// Screens a search result can open.
enum AppFeature: String, CaseIterable, Identifiable {
    case scanner, findABrick, seeWhatYouCanBuild, mosaicStudio, setCollection, setModels
    case storageBins, community, puzzles, minifigureCatalog
    case scanToSet, describeSet, forgedSets, scanOneBrick, rebuildableSets, colorCalibration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scanner: return "Scanner"
        case .findABrick: return "Find a Brick"
        case .seeWhatYouCanBuild: return "See What You Can Build"
        case .mosaicStudio: return L10n.mosaicTitle
        case .setCollection: return "Set Collection"
        case .setModels: return "Set Models"
        case .storageBins: return "Storage Bins"
        case .community: return "Community"
        case .puzzles: return "Puzzles & Games"
        case .minifigureCatalog: return "Minifigures"
        case .scanToSet: return "Scan to Set"
        case .describeSet: return "Describe a Set"
        case .forgedSets: return "My Forged Sets"
        case .scanOneBrick: return "Scan One Brick"
        case .rebuildableSets: return "Sets You Can Rebuild"
        case .colorCalibration: return "Color Calibration"
        }
    }

    var subtitle: String {
        switch self {
        case .scanner: return "Auto-detects minifigures or brick piles"
        case .findABrick: return "Search the catalog and locate pieces in any pile"
        case .seeWhatYouCanBuild: return "Turn your scanned bricks into buildable projects with 3D steps"
        case .mosaicStudio: return L10n.mosaicSubheadline
        case .setCollection: return "Track LEGO sets and check piece completion"
        case .setModels: return "Browse bundled LDraw set models and follow them step by step"
        case .storageBins: return "Organize pieces by physical storage location"
        case .community: return "Share builds and discover creations"
        case .puzzles: return "Guess builds from clues and test your knowledge"
        case .minifigureCatalog: return "Browse 16,000+ figures or scan a torso to identify one."
        case .scanToSet: return "Scan a real object from every side and \(AppConfig.appName) forges a buildable brick model of it — with a parts list and instructions."
        case .describeSet: return "Describe what you want to build and \(AppConfig.appName) forges a brick model you can build for real — with a parts list and instructions."
        case .forgedSets: return "Sets you create with Set Forge — from a photo, a 3D scan, or a description — are saved here."
        case .scanOneBrick: return "Center one brick in the frame to identify it"
        case .rebuildableSets: return "See which of your owned sets are fully buildable from your pieces"
        case .colorCalibration: return "Photograph a known LEGO piece in each color to calibrate color recognition for your lighting"
        }
    }

    var icon: String {
        switch self {
        case .scanner: return "camera.viewfinder"
        case .findABrick: return "magnifyingglass"
        case .seeWhatYouCanBuild: return "hammer.fill"
        case .mosaicStudio: return "square.grid.3x3.fill"
        case .setCollection: return "shippingbox.fill"
        case .setModels: return "cube.transparent"
        case .storageBins: return "tray.2.fill"
        case .community: return "person.3.fill"
        case .puzzles: return "puzzlepiece.fill"
        case .minifigureCatalog: return "person.fill"
        case .scanToSet: return "cube.fill"
        case .describeSet: return "text.bubble.fill"
        case .forgedSets: return "wand.and.stars"
        case .scanOneBrick: return "viewfinder"
        case .rebuildableSets: return "arrow.triangle.2.circlepath"
        case .colorCalibration: return "paintpalette.fill"
        }
    }

    var keywords: [String] {
        switch self {
        case .scanner: return ["scan", "camera", "identify", "minifigure", "pile", "bricks"]
        case .findABrick: return ["find", "locate", "search", "piece", "part", "catalog"]
        case .seeWhatYouCanBuild: return ["builds", "projects", "ideas", "3D instructions", "step-by-step"]
        case .mosaicStudio: return ["mosaic", "photo", "picture", "art", "parts list", "instructions"]
        case .setCollection: return ["sets", "collection", "completion", "rebrickable"]
        case .setModels: return ["ldraw", "3D", "model", "instructions"]
        case .storageBins: return ["bins", "storage", "organize", "sort"]
        case .community: return ["share", "feed", "follow", "comment", "posts"]
        case .puzzles: return ["games", "clues", "daily challenge", "streak", "score"]
        case .minifigureCatalog: return ["minifigs", "figures", "torso", "collection"]
        case .scanToSet: return ["set forge", "3D", "photogrammetry", "model", "photo", "video", "object"]
        case .describeSet: return ["set forge", "ai", "text", "prompt", "voice"]
        case .forgedSets: return ["set forge", "gallery", "3D", "stl", "print"]
        case .scanOneBrick: return ["single", "one", "brick", "identify", "color"]
        case .rebuildableSets: return ["sets", "buildable", "complete", "rebuild", "inventory"]
        case .colorCalibration: return ["color", "lighting", "calibrate", "white balance"]
        }
    }
}

enum AppTutorial: Hashable {
    case scanGuide(page: Int)
    case welcomeTour(page: Int)
    case buildExplainer
}

/// A collapsible section of `SettingsView`; search results jump to these.
enum SettingsAnchor: String, CaseIterable, Identifiable {
    case appearance, puzzles, scanning, account, subscription, privacy, help
    case icloud, setCollection, data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .puzzles: return "Puzzles"
        case .scanning: return "Scanning"
        case .account: return "Account"
        case .subscription: return "Subscription"
        case .privacy: return "Privacy"
        case .help: return "Help & Support"
        case .icloud: return "iCloud Sync"
        case .setCollection: return "Set Collection"
        case .data: return "Data & About"
        }
    }
}

enum AppSearchDestination: Hashable {
    case feature(AppFeature)
    case setting(SettingsAnchor)
    case helpArticle(question: String)
    case tutorial(AppTutorial)
    case tips
    case privacyPolicy
    case paywall
    case buildIdea(UUID)
    case set(String)
    case minifigure(String)
}

// MARK: - Text matching

enum AppSearchText {
    static let searchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func fold(_ text: String) -> String {
        text.folding(options: searchOptions, locale: nil)
    }

    /// Whitespace-separated, case- and diacritic-folded query tokens.
    static func tokens(_ query: String) -> [String] {
        fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    enum MatchKind: Int {
        case none = 0
        case inside
        case wordStart
    }

    /// `folded` must already be folded; `token` comes from `tokens(_:)`.
    static func match(_ token: String, in folded: String) -> MatchKind {
        guard !token.isEmpty else { return .none }
        var best = MatchKind.none
        var searchRange = folded.startIndex..<folded.endIndex
        while let found = folded.range(of: token, range: searchRange) {
            if found.lowerBound == folded.startIndex { return .wordStart }
            let previous = folded[folded.index(before: found.lowerBound)]
            if !(previous.isLetter || previous.isNumber) { return .wordStart }
            best = .inside
            searchRange = found.upperBound..<folded.endIndex
        }
        return best
    }

    /// Weighted score, or `nil` when any token is missing from every field.
    static func score(
        tokens: [String],
        title: String,
        keywords: String,
        breadcrumb: String,
        body: String
    ) -> Int? {
        guard !tokens.isEmpty else { return nil }
        var total = 0
        for token in tokens {
            var best = 0
            switch match(token, in: title) {
            case .wordStart: best = 100
            case .inside: best = 60
            case .none: break
            }
            if best < 50 {
                switch match(token, in: keywords) {
                case .wordStart: best = max(best, 50)
                case .inside: best = max(best, 30)
                case .none: break
                }
            }
            if best < 25 {
                switch match(token, in: body) {
                case .wordStart: best = max(best, 25)
                case .inside: best = max(best, 10)
                case .none: break
                }
            }
            if best < 20 {
                switch match(token, in: breadcrumb) {
                case .wordStart: best = max(best, 20)
                case .inside: best = max(best, 8)
                case .none: break
                }
            }
            if best == 0 { return nil }
            total += best
        }
        if tokens.count > 1, title.contains(tokens.joined(separator: " ")) { total += 50 }
        return total
    }

    /// Ranges of every token occurrence in the original (unfolded) text.
    static func matchRanges(of tokens: [String], in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for token in tokens where !token.isEmpty {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: token, options: searchOptions, range: searchRange) {
                ranges.append(found)
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return ranges
    }

    /// A short excerpt of `text` around the first token match, so a body hit
    /// shows its context. Returns the start of the text when nothing matches.
    static func snippet(of text: String, tokens: [String], maxLength: Int = 140) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        guard flat.count > maxLength else { return flat }
        guard let first = matchRanges(of: tokens, in: flat).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return String(flat.prefix(maxLength)) + "…"
        }
        let lead = 40
        let startOffset = max(0, flat.distance(from: flat.startIndex, to: first.lowerBound) - lead)
        let start = flat.index(flat.startIndex, offsetBy: startOffset)
        let end = flat.index(start, offsetBy: min(maxLength, flat.distance(from: start, to: flat.endIndex)))
        var excerpt = String(flat[start..<end]).trimmingCharacters(in: .whitespaces)
        if startOffset > 0 { excerpt = "…" + excerpt }
        if end < flat.endIndex { excerpt += "…" }
        return excerpt
    }
}

// MARK: - Entries and results

struct AppSearchEntry: Identifiable {
    let id: String
    let category: AppSearchCategory
    let title: String
    let body: String
    let breadcrumb: String?
    let icon: String
    let destination: AppSearchDestination
    let keywords: [String]

    fileprivate let foldedTitle: String
    fileprivate let foldedBody: String
    fileprivate let foldedKeywords: String
    fileprivate let foldedBreadcrumb: String

    init(
        id: String,
        category: AppSearchCategory,
        title: String,
        body: String = "",
        breadcrumb: String? = nil,
        icon: String? = nil,
        destination: AppSearchDestination,
        keywords: [String] = []
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.body = body
        self.breadcrumb = breadcrumb
        self.icon = icon ?? category.icon
        self.destination = destination
        self.keywords = keywords
        self.foldedTitle = AppSearchText.fold(title)
        self.foldedBody = AppSearchText.fold(body)
        self.foldedKeywords = AppSearchText.fold(keywords.joined(separator: " "))
        self.foldedBreadcrumb = AppSearchText.fold(breadcrumb ?? "")
    }

    fileprivate func score(tokens: [String]) -> Int? {
        AppSearchText.score(
            tokens: tokens,
            title: foldedTitle,
            keywords: foldedKeywords,
            breadcrumb: foldedBreadcrumb,
            body: foldedBody
        )
    }
}

struct AppSearchResult: Identifiable {
    let entry: AppSearchEntry
    let score: Int
    var id: String { entry.id }
}

struct AppSearchGroup: Identifiable {
    let category: AppSearchCategory
    let results: [AppSearchResult]
    /// Matches before the per-group cap was applied.
    let totalCount: Int

    var id: String { category.rawValue }
    var isTruncated: Bool { totalCount > results.count }
}

// MARK: - Service

/// App-wide search over features, settings, help, tutorials, tips, privacy
/// text and the build, set and minifigure catalogs. Static content is read
/// from the same data the screens render, so results cannot drift from it.
@MainActor
final class AppSearchService {
    static let shared = AppSearchService()

    static let maxResultsPerCategory = 25
    static let minimumQueryLength = 2

    private lazy var staticEntries: [AppSearchEntry] = Self.makeStaticEntries()
    private lazy var buildIdeaEntries: [AppSearchEntry] = Self.makeBuildIdeaEntries()
    private lazy var setEntries: [AppSearchEntry] = Self.makeSetEntries()

    private struct MinifigRow {
        let figure: Minifigure
        let foldedTitle: String
        let foldedBody: String
    }
    private var minifigRows: [MinifigRow] = []
    private var minifigRowsSourceCount = -1

    init() {}

    /// Builds the lazily-created indexes so the first keystroke is not slow.
    func warmUp() {
        _ = staticEntries
        _ = buildIdeaEntries
        _ = setEntries
        refreshMinifigRows()
    }

    func search(_ query: String) -> [AppSearchGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumQueryLength else { return [] }
        let tokens = AppSearchText.tokens(trimmed)
        guard !tokens.isEmpty else { return [] }

        var scored: [AppSearchCategory: [AppSearchResult]] = [:]

        for entries in [staticEntries, buildIdeaEntries, setEntries] {
            for entry in entries {
                if let score = entry.score(tokens: tokens) {
                    scored[entry.category, default: []].append(AppSearchResult(entry: entry, score: score))
                }
            }
        }

        refreshMinifigRows()
        var minifigHits: [(row: MinifigRow, score: Int)] = []
        for row in minifigRows {
            if let score = AppSearchText.score(
                tokens: tokens,
                title: row.foldedTitle,
                keywords: "",
                breadcrumb: "",
                body: row.foldedBody
            ) {
                minifigHits.append((row, score))
            }
        }

        var groups: [AppSearchGroup] = []
        for category in AppSearchCategory.allCases {
            if category == .minifigure {
                guard !minifigHits.isEmpty else { continue }
                let top = minifigHits
                    .sorted { lhs, rhs in
                        lhs.score != rhs.score
                            ? lhs.score > rhs.score
                            : lhs.row.figure.name.localizedCaseInsensitiveCompare(rhs.row.figure.name) == .orderedAscending
                    }
                    .prefix(Self.maxResultsPerCategory)
                    .map { AppSearchResult(entry: Self.entry(for: $0.row.figure), score: $0.score) }
                groups.append(AppSearchGroup(category: category, results: Array(top), totalCount: minifigHits.count))
                continue
            }

            guard var results = scored[category], !results.isEmpty else { continue }
            results.sort { lhs, rhs in
                lhs.score != rhs.score
                    ? lhs.score > rhs.score
                    : lhs.entry.title.localizedCaseInsensitiveCompare(rhs.entry.title) == .orderedAscending
            }
            let total = results.count
            if category.isCapped { results = Array(results.prefix(Self.maxResultsPerCategory)) }
            groups.append(AppSearchGroup(category: category, results: results, totalCount: total))
        }
        return groups
    }

    // MARK: Minifigures

    private func refreshMinifigRows() {
        let figures = MinifigureCatalog.shared.allFigures
        guard figures.count != minifigRowsSourceCount else { return }
        minifigRows = figures.map { figure in
            MinifigRow(
                figure: figure,
                foldedTitle: AppSearchText.fold(figure.name),
                foldedBody: AppSearchText.fold("\(figure.theme) \(figure.id)")
            )
        }
        minifigRowsSourceCount = figures.count
    }

    private static func entry(for figure: Minifigure) -> AppSearchEntry {
        var details = [figure.theme]
        if figure.year > 0 { details.append(String(figure.year)) }
        details.append("\(figure.partCount) parts")
        return AppSearchEntry(
            id: "minifigure.\(figure.id)",
            category: .minifigure,
            title: figure.name,
            body: details.joined(separator: " · "),
            breadcrumb: "Minifigure",
            icon: figure.fallbackSystemImage,
            destination: .minifigure(figure.id)
        )
    }

    // MARK: Catalog entries

    private static func makeBuildIdeaEntries() -> [AppSearchEntry] {
        BuildSuggestionEngine.shared.allProjects.map { project in
            var text = [project.description]
            if let fact = project.funFact { text.append(fact) }
            for step in project.instructions {
                text.append(step.instruction)
                if let tip = step.tip { text.append(tip) }
            }
            return AppSearchEntry(
                id: "build.\(project.id.uuidString)",
                category: .buildIdea,
                title: project.name,
                body: text.joined(separator: " "),
                breadcrumb: "\(project.category.rawValue) · \(project.difficulty.rawValue)",
                icon: project.imageSystemName,
                destination: .buildIdea(project.id)
            )
        }
    }

    private static func makeSetEntries() -> [AppSearchEntry] {
        LegoSetCatalog.shared.sets.map { set in
            AppSearchEntry(
                id: "set.\(set.setNumber)",
                category: .set,
                title: set.name,
                body: "Set \(set.setNumber) · \(set.theme) · \(set.year) · \(set.pieceCount) pieces",
                breadcrumb: set.theme,
                destination: .set(set.setNumber)
            )
        }
    }

    // MARK: Static entries

    private static func makeStaticEntries() -> [AppSearchEntry] {
        var entries: [AppSearchEntry] = []
        entries += featureEntries()
        entries += settingEntries()
        entries += helpEntries()
        entries += tutorialEntries()
        entries += tipEntries()
        entries += legalEntries()
        return entries
    }

    private static func featureEntries() -> [AppSearchEntry] {
        var entries = AppFeature.allCases.map { feature in
            AppSearchEntry(
                id: "feature.\(feature.rawValue)",
                category: .feature,
                title: feature.title,
                body: feature.subtitle,
                icon: feature.icon,
                destination: feature == .seeWhatYouCanBuild ? .tutorial(.buildExplainer) : .feature(feature),
                keywords: feature.keywords
            )
        }
        let proFeatures: [(title: String, icon: String, keywords: [String])] = [
            ("Unlimited Scans", "infinity", ["daily scans", "limit"]),
            ("All Build Ideas", "hammer.fill", ["200+", "library", "projects"]),
            ("AI Build Ideas", "sparkles", ["ai", "suggestions"]),
            ("3D Model Export", "cube.fill", ["3D", "export", "model"]),
            ("STL Print Export", "printer.fill", ["stl", "3D", "3D printing", "print"]),
            ("iCloud Sync", "icloud.fill", ["sync", "devices"]),
            ("CSV/PDF Export", "square.and.arrow.up", ["csv", "pdf", "export", "inventory"]),
            ("Natural Language Search", "text.magnifyingglass", ["search", "piece", "ai"]),
        ]
        entries += proFeatures.map { feature in
            AppSearchEntry(
                id: "feature.pro.\(feature.title)",
                category: .feature,
                title: feature.title,
                body: "Included with \(AppConfig.appName) Pro.",
                breadcrumb: "\(AppConfig.appName) Pro",
                icon: feature.icon,
                destination: .paywall,
                keywords: feature.keywords + ["pro", "upgrade"]
            )
        }
        return entries
    }

    private static func settingEntries() -> [AppSearchEntry] {
        func setting(_ anchor: SettingsAnchor, _ title: String, _ body: String, _ keywords: [String] = []) -> AppSearchEntry {
            AppSearchEntry(
                id: "setting.\(anchor.rawValue).\(title)",
                category: .setting,
                title: title,
                body: body,
                breadcrumb: "Settings › \(anchor.title)",
                icon: "gearshape.fill",
                destination: .setting(anchor),
                keywords: keywords
            )
        }

        let scanModes = ScanSettings.ScanMode.allCases.map { "\($0.rawValue): \($0.description)" }
        let reconstruction = ScanSettings.MeshReconstructionMode.allCases.map { "\($0.rawValue): \($0.description)" }
        let identification = ScanSettings.IdentificationMode.allCases.map { "\($0.rawValue): \($0.description)" }

        return [
            setting(.appearance, "Appearance",
                    "Choose \(ThemeManager.AppearanceMode.allCases.map(\.rawValue).joined(separator: ", ")) appearance.",
                    ["dark mode", "light mode", "theme"]),
            setting(.appearance, "Color Theme",
                    ThemeManager.ColorTheme.allCases.map(\.rawValue).joined(separator: ", "),
                    ["colors", "palette"]),
            setting(.puzzles, "Puzzle Grid",
                    "Grid size of the mystery build: \(PuzzleGridPreset.allCases.map(\.label).joined(separator: ", ")).",
                    ["puzzle", "size"]),
            setting(.puzzles, "Squares Revealed per Hint",
                    "Each hint uncovers grid size ÷ 4 random squares of the mystery build.",
                    ["hint", "puzzle"]),
            setting(.scanning, "Scan Mode", scanModes.joined(separator: " "), ["regular", "detailed", "capture"]),
            setting(.scanning, "Piece Location Snapshots",
                    "Enable location snapshots, composite mode and pre-render on scan complete.",
                    ["composite", "photo", "where"]),
            setting(.scanning, "3D Reconstruction",
                    "Method used by Set Forge to turn a scan into a 3D model. " + reconstruction.joined(separator: " "),
                    ["3D", "set forge", "mesh", "cloud", "on-device"]),
            setting(.scanning, "Help Improve \(AppConfig.appName) for Everyone",
                    "Shares anonymized brick corrections (no photos — just an on-device fingerprint and the label) so the scanner gets more accurate for all users. Turn off anytime.",
                    ["community", "corrections", "privacy", "share"]),
            setting(.scanning, "Scan Locations",
                    "Tag scans with location, set the “Near Me” radius, or forget locations on saved scans.",
                    ["gps", "map", "near me", "geolocation"]),
            setting(.scanning, "Color Calibration",
                    "Calibrate color recognition to your lighting.",
                    ["white balance", "lighting"]),
            setting(.scanning, "Scanner Identification Mode",
                    identification.joined(separator: " ")
                        + " Strict Offline blocks all network-backed scan help. Offline First allows previously cached references but no new downloads during a scan. Assisted enables on-demand reference fetches and Brickognize verification.",
                    ["offline", "brickognize", "network", "assisted"]),
            setting(.account, "Sign In with Apple",
                    "Sign in to post builds, comment and follow builders in the community.",
                    ["login", "account", "community", "sign out"]),
            setting(.subscription, "Plan",
                    "See whether you are on Free or \(AppConfig.appName) Pro, Family Sharing status and remaining daily scans.",
                    ["pro", "free", "family sharing", "daily scans"]),
            setting(.subscription, "Upgrade to Pro",
                    "Unlock unlimited scans, AI build ideas, 3D and STL export, iCloud sync and more.",
                    ["paywall", "purchase", "subscription"]),
            setting(.subscription, "Restore Purchases",
                    "Restore a previous \(AppConfig.appName) Pro purchase.",
                    ["purchase", "restore", "pro"]),
            setting(.privacy, "Usage Analytics",
                    "Opt in or out of anonymous usage analytics.",
                    ["analytics", "tracking", "privacy", "data"]),
            setting(.privacy, "Privacy Policy",
                    "Read how \(AppConfig.appName) handles your data.",
                    ["privacy", "policy", "legal", "coppa"]),
            setting(.help, "Help & FAQ", "Open the Help Center with guides and frequently asked questions.", ["support", "faq"]),
            setting(.help, "Reset Feature Tips", "Show the dismissed feature tips again.", ["tips", "hints"]),
            setting(.icloud, "iCloud Sync",
                    "Keep inventories, sets and storage bins in sync across your devices. Shows sync status and last sync, and lets you sync now.",
                    ["sync", "cloud", "backup", "devices"]),
            setting(.setCollection, "Auto-Download Thumbnails",
                    "Automatically fetch the official Rebrickable photo whenever a set is identified or added to your collection.",
                    ["rebrickable", "images", "photos"]),
            setting(.setCollection, "Rebrickable API Key",
                    "\(AppConfig.appName) uses a built-in parts service first; only if it's unavailable does it use your key. A free Rebrickable key is stored on this device and synced via iCloud.",
                    ["api", "key", "parts service"]),
            setting(.setCollection, "Download Missing Thumbnails",
                    "Download set photos that are missing from your collection.",
                    ["images", "sets"]),
            setting(.data, "Clear Scan History", "Permanently remove all saved scan sessions.", ["delete", "history", "scans"]),
            setting(.data, "Clear Minifigure Image Cache",
                    "Catalog images you've viewed are saved on-device so the minifigure scanner can identify them offline.",
                    ["cache", "storage", "images", "offline"]),
            setting(.data, "About",
                    "Version, AI Engine (Core ML, on-device), parts catalog size and bundled reference images.",
                    ["version", "build", "core ml", "parts catalog"]),
        ]
    }

    private static func helpEntries() -> [AppSearchEntry] {
        helpSections.flatMap { section in
            section.items.map { item in
                AppSearchEntry(
                    id: "help.\(section.title).\(item.question)",
                    category: .helpArticle,
                    title: item.question,
                    body: item.answer,
                    breadcrumb: "Help › \(section.title)",
                    icon: item.icon,
                    destination: .helpArticle(question: item.question)
                )
            }
        }
    }

    private static func tutorialEntries() -> [AppSearchEntry] {
        var entries: [AppSearchEntry] = []

        for (index, page) in ScanGuideView.pages.enumerated() {
            let steps = page.steps.map(\.text).joined(separator: " ")
            entries.append(AppSearchEntry(
                id: "tutorial.scan.\(index)",
                category: .tutorial,
                title: page.title,
                body: "\(page.subtitle). \(steps)",
                breadcrumb: "Tutorial › How to Scan",
                icon: page.icon,
                destination: .tutorial(.scanGuide(page: index))
            ))
        }

        for (index, page) in ReplayOnboardingView.pages.enumerated() {
            entries.append(AppSearchEntry(
                id: "tutorial.tour.\(index)",
                category: .tutorial,
                title: page.title,
                body: page.description,
                breadcrumb: "Tutorial › Welcome Tour",
                icon: page.icon,
                destination: .tutorial(.welcomeTour(page: index))
            ))
        }

        entries.append(AppSearchEntry(
            id: "tutorial.build",
            category: .tutorial,
            title: BuildFeatureExplainerView.headline,
            body: "\(BuildFeatureExplainerView.subheadline) \(BuildFeatureExplainerView.whereToFindText.replacingOccurrences(of: "**", with: ""))",
            breadcrumb: "Tutorial › Build Ideas",
            icon: "hammer.fill",
            destination: .tutorial(.buildExplainer)
        ))
        for step in BuildFeatureExplainerView.steps {
            entries.append(AppSearchEntry(
                id: "tutorial.build.\(step.number)",
                category: .tutorial,
                title: step.title,
                body: step.detail.replacingOccurrences(of: "“", with: "").replacingOccurrences(of: "”", with: ""),
                breadcrumb: "Tutorial › Build Ideas › Step \(step.number)",
                icon: step.icon,
                destination: .tutorial(.buildExplainer)
            ))
        }
        return entries
    }

    private static func tipEntries() -> [AppSearchEntry] {
        FeatureTipInfo.all.map { tip in
            AppSearchEntry(
                id: "tip.\(tip.title)",
                category: .tip,
                title: tip.title,
                body: tip.detail,
                breadcrumb: "Feature Tips",
                icon: tip.icon,
                destination: .tips
            )
        }
    }

    private static func legalEntries() -> [AppSearchEntry] {
        PrivacyPolicyView.sections.map { section in
            AppSearchEntry(
                id: "legal.\(section.title)",
                category: .legal,
                title: section.title,
                body: section.body,
                breadcrumb: "Privacy Policy",
                icon: "hand.raised.fill",
                destination: .privacyPolicy
            )
        }
    }
}
