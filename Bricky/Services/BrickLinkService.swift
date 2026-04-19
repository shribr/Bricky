import Foundation

/// URL builders for BrickLink and Rebrickable deep-links.
/// No API calls, no auth required — live values open in Safari on the user's device.
///
/// ### Why both services?
/// BrickLink minifigure ids (e.g. `sp036`, `sw0001a`) are *different* from
/// Rebrickable fig ids (e.g. `fig-001234`). The Rebrickable data dumps we
/// use as our catalog source only contain Rebrickable ids. So for
/// minifigure pages we link to Rebrickable (which accepts our fig-ids), and
/// offer BrickLink search-by-name as a secondary action.
///
/// Parts are different: part numbers like `3001` line up across both
/// catalogs, so part deep-links go directly to BrickLink.
enum BrickLinkService {

    private static let blBase = "https://www.bricklink.com/v2/catalog/catalogitem.page"
    private static let blSearchBase = "https://www.bricklink.com/v2/search.page"
    private static let rbBase = "https://rebrickable.com"

    // MARK: - Parts (BrickLink)

    /// Page for a part (any color).
    /// e.g. https://www.bricklink.com/v2/catalog/catalogitem.page?P=3626c
    static func partURL(_ partNumber: String) -> URL? {
        guard let escaped = partNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "\(blBase)?P=\(escaped)")
    }

    /// Page for a part filtered by color.
    /// e.g. https://www.bricklink.com/v2/catalog/catalogitem.page?P=3626c&idColor=3
    static func partURL(_ partNumber: String, color: LegoColor) -> URL? {
        guard let escaped = partNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let colorId = BrickLinkColorMap.id(for: color)
        return URL(string: "\(blBase)?P=\(escaped)&idColor=\(colorId)")
    }

    /// Price guide page for a part + color.
    static func priceGuideURL(part partNumber: String, color: LegoColor) -> URL? {
        guard let escaped = partNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let colorId = BrickLinkColorMap.id(for: color)
        return URL(string: "\(blBase)?P=\(escaped)&idColor=\(colorId)#T=P")
    }

    /// BrickLink **search** for a part. More forgiving than the catalog
    /// item page: works for compound part numbers (e.g. `973pb1234c01`),
    /// printed variants, and modified torsos that don't have an exact
    /// catalogitem.page entry. Filtered to the Parts category.
    /// e.g. https://www.bricklink.com/v2/search.page?q=973pb1234&category[]=P
    static func partSearchURL(_ partNumber: String) -> URL? {
        guard var comps = URLComponents(string: blSearchBase) else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "q", value: partNumber),
            URLQueryItem(name: "category[]", value: "P")
        ]
        return comps.url
    }

    // MARK: - Minifigures (Rebrickable)

    /// Rebrickable page for a minifigure (uses our catalog's fig-id).
    /// e.g. https://rebrickable.com/minifigs/fig-001234/
    static func rebrickableMinifigureURL(_ figId: String) -> URL? {
        guard let escaped = figId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(rbBase)/minifigs/\(escaped)/")
    }

    // MARK: - Minifigures (BrickLink search fallback)

    /// BrickLink minifigure search by name.
    /// Used because Rebrickable fig-ids don't map to BrickLink ids.
    /// e.g. https://www.bricklink.com/v2/search.page?q=Star+Wars+Anakin&category[]=M
    static func brickLinkMinifigureSearchURL(name: String) -> URL? {
        guard var comps = URLComponents(string: blSearchBase) else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "category[]", value: "M")
        ]
        return comps.url
    }

    // MARK: - Wanted list

    /// Page where users paste BrickLink Wanted List XML.
    static func wantedListImportURL() -> URL? {
        URL(string: "https://www.bricklink.com/v2/wanted/upload.page")
    }

    // MARK: - Deprecated shims

    /// Historical shim. Prefer `rebrickableMinifigureURL(_:)` because
    /// BrickLink minifigure ids don't match our catalog's Rebrickable ids.
    @available(*, deprecated, renamed: "rebrickableMinifigureURL(_:)")
    static func minifigureURL(_ figId: String) -> URL? {
        rebrickableMinifigureURL(figId)
    }

    @available(*, deprecated, message: "Rebrickable fig-ids don't map to BrickLink. Use brickLinkMinifigureSearchURL(name:) or rebrickableMinifigureURL(_:).")
    static func minifigurePriceGuideURL(_ figId: String) -> URL? {
        rebrickableMinifigureURL(figId)
    }
}
