import Foundation

/// Centralized localized string access for Bricky.
/// Uses the String Catalog (Localizable.xcstrings) with keys for EN, ES, FR, DE, JA.
enum L10n {

    // MARK: - App
    static let appName = String(localized: "app.name")
    static let appTagline = String(localized: "app.tagline")
    static let appDescription = String(localized: "app.description")

    // MARK: - Home
    static let scanPieces = String(localized: "home.scanPieces")
    static let scanPiecesDescription = String(localized: "home.scanPieces.description")
    static let tryDemoMode = String(localized: "home.tryDemoMode")
    static let tryDemoModeDescription = String(localized: "home.tryDemoMode.description")
    static let currentSession = String(localized: "home.currentSession")
    static let savedInventories = String(localized: "home.savedInventories")
    static let howItWorks = String(localized: "home.howItWorks")

    // MARK: - Common
    static let continueAction = String(localized: "common.continue")
    static let done = String(localized: "common.done")
    static let cancel = String(localized: "common.cancel")
    static let save = String(localized: "common.save")
    static let delete = String(localized: "common.delete")
    static let share = String(localized: "common.share")
    static let settings = String(localized: "common.settings")

    // MARK: - Scanning
    static let scanTitle = String(localized: "scan.title")
    static let pointCamera = String(localized: "scan.pointCamera")
    static let analyzing = String(localized: "scan.analyzing")
    static let lightingWarning = String(localized: "scan.lightingWarning")

    static func piecesFound(_ count: Int) -> String {
        String(localized: "scan.piecesFound", defaultValue: "\(count) pieces found")
    }

    // MARK: - Catalog
    static let catalogTitle = String(localized: "catalog.title")
    static let catalogSearch = String(localized: "catalog.search")
    static let totalPieces = String(localized: "catalog.totalPieces")
    static let uniqueTypes = String(localized: "catalog.uniqueTypes")

    // MARK: - Builds
    static let buildsTitle = String(localized: "builds.title")
    static let overview = String(localized: "builds.overview")
    static let pieces = String(localized: "builds.pieces")
    static let instructions = String(localized: "builds.instructions")
    static let difficulty = String(localized: "builds.difficulty")
    static let time = String(localized: "builds.time")
    static let match = String(localized: "builds.match")
    static let about = String(localized: "builds.about")
    static let allPieces = String(localized: "builds.allPieces")
    static let missingPieces = String(localized: "builds.missingPieces")
    static let requiredPieces = String(localized: "builds.requiredPieces")
    static let buildComplete = String(localized: "builds.buildComplete")
    static let stepByStep3D = String(localized: "builds.3dStepByStep")
    static let viewIn3D = String(localized: "builds.viewIn3d")
    static let findInPile = String(localized: "builds.findInPile")
    static let favorites = String(localized: "builds.favorites")

    // MARK: - 3D Model
    static let preview3D = String(localized: "model.3dPreview")
    static let instructions3D = String(localized: "model.3dInstructions")
    static let exportSTL = String(localized: "model.exportSTL")

    // MARK: - Onboarding
    static let welcome = String(localized: "onboarding.welcome")
    static let getStarted = String(localized: "onboarding.getStarted")

    // MARK: - Results
    static let scanResults = String(localized: "results.scanResults")
    static let viewCatalog = String(localized: "results.viewCatalog")
    static let viewBuilds = String(localized: "results.viewBuilds")
    static let saveInventory = String(localized: "results.saveInventory")

    // MARK: - Accessibility
    static let addToFavorites = String(localized: "accessibility.addToFavorites")
    static let removeFromFavorites = String(localized: "accessibility.removeFromFavorites")
    static let shareBuild = String(localized: "accessibility.shareBuild")
}
