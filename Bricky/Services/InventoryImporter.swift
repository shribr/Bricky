import Foundation

/// Imports inventory data from CSV or BrickLink Wanted List XML files.
struct InventoryImporter {

    enum ImportError: LocalizedError {
        case invalidFormat(String)
        case emptyFile
        case unsupportedFileType(String)

        var errorDescription: String? {
            switch self {
            case .invalidFormat(let detail): return "Invalid file format: \(detail)"
            case .emptyFile: return "The file is empty."
            case .unsupportedFileType(let ext): return "Unsupported file type: .\(ext). Use .csv or .xml."
            }
        }
    }

    /// Detect format by file extension and import.
    static func importFile(at url: URL) throws -> [InventoryStore.InventoryPiece] {
        let ext = url.pathExtension.lowercased()
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw ImportError.emptyFile }
        let content = String(decoding: data, as: UTF8.self)

        switch ext {
        case "csv":
            return try importCSV(content)
        case "xml":
            return try importBrickLinkXML(content)
        default:
            throw ImportError.unsupportedFileType(ext)
        }
    }

    // MARK: - CSV Import

    /// Parse CSV with header row. Supports Bricky export format and generic formats.
    static func importCSV(_ content: String) throws -> [InventoryStore.InventoryPiece] {
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { throw ImportError.invalidFormat("CSV must have a header row and at least one data row.") }

        let header = parseCSVLine(lines[0]).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // Resolve column indices — flexible matching
        let partNumberIdx = header.firstIndex(where: { $0.contains("part") && $0.contains("number") || $0 == "itemid" || $0 == "partno" || $0 == "part" || $0 == "part #" })
        let nameIdx = header.firstIndex(where: { $0 == "name" || $0 == "description" || $0 == "remarks" })
        let categoryIdx = header.firstIndex(where: { $0 == "category" || $0 == "type" || $0 == "itemtype" })
        let colorIdx = header.firstIndex(where: { $0 == "color" || $0 == "colour" || $0 == "color name" })
        let quantityIdx = header.firstIndex(where: { $0 == "quantity" || $0 == "qty" || $0 == "minqty" || $0 == "count" })
        let studsWideIdx = header.firstIndex(where: { $0 == "studs wide" || $0 == "studswide" || $0 == "width" })
        let studsLongIdx = header.firstIndex(where: { $0 == "studs long" || $0 == "studslong" || $0 == "length" })
        let heightIdx = header.firstIndex(where: { $0 == "height units" || $0 == "heightunits" || $0 == "height" })

        guard partNumberIdx != nil || nameIdx != nil else {
            throw ImportError.invalidFormat("CSV must have a 'Part Number' or 'Name' column.")
        }

        var pieces: [InventoryStore.InventoryPiece] = []

        for i in 1..<lines.count {
            let fields = parseCSVLine(lines[i])
            guard !fields.isEmpty else { continue }

            let partNumber = safeField(fields, at: partNumberIdx) ?? "unknown"
            let name = safeField(fields, at: nameIdx) ?? partNumber
            let categoryStr = safeField(fields, at: categoryIdx) ?? "brick"
            let colorStr = safeField(fields, at: colorIdx) ?? "gray"
            let quantity = Int(safeField(fields, at: quantityIdx) ?? "1") ?? 1
            let studsWide = Int(safeField(fields, at: studsWideIdx) ?? "2") ?? 2
            let studsLong = Int(safeField(fields, at: studsLongIdx) ?? "2") ?? 2
            let heightUnits = Int(safeField(fields, at: heightIdx) ?? "3") ?? 3

            let category = PieceCategory(rawValue: categoryStr) ?? inferCategory(from: name)
            let color = LegoColor(fromString: colorStr) ?? inferColor(from: colorStr)

            let piece = InventoryStore.InventoryPiece(
                partNumber: partNumber,
                name: name,
                category: category,
                color: color,
                quantity: max(1, quantity),
                dimensions: PieceDimensions(studsWide: studsWide, studsLong: studsLong, heightUnits: heightUnits)
            )
            pieces.append(piece)
        }

        guard !pieces.isEmpty else { throw ImportError.invalidFormat("No valid pieces found in CSV.") }
        return pieces
    }

    // MARK: - BrickLink XML Import

    /// Parse BrickLink Wanted List XML format.
    static func importBrickLinkXML(_ content: String) throws -> [InventoryStore.InventoryPiece] {
        let parser = BrickLinkXMLParser(xml: content)
        let items = parser.parse()
        guard !items.isEmpty else { throw ImportError.invalidFormat("No <ITEM> elements found in XML.") }

        return items.map { item in
            let category = inferCategory(from: item.partNumber)
            let color = brickLinkColorToLegoColor(item.colorId)
            let name = item.remarks.isEmpty ? item.partNumber : item.remarks

            return InventoryStore.InventoryPiece(
                partNumber: item.partNumber,
                name: name,
                category: category,
                color: color,
                quantity: max(1, item.quantity),
                dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3)
            )
        }
    }

    // MARK: - CSV Parsing Helpers

    /// Parse a single CSV line respecting quoted fields.
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private static func safeField(_ fields: [String], at index: Int?) -> String? {
        guard let idx = index, idx < fields.count else { return nil }
        let value = fields[idx].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    // MARK: - Color/Category Inference

    private static func inferCategory(from text: String) -> PieceCategory {
        let lower = text.lowercased()
        if lower.contains("plate") { return .plate }
        if lower.contains("tile") { return .tile }
        if lower.contains("slope") { return .slope }
        if lower.contains("arch") { return .arch }
        if lower.contains("round") { return .round }
        if lower.contains("technic") { return .technic }
        if lower.contains("wheel") { return .wheel }
        if lower.contains("connector") || lower.contains("pin") { return .connector }
        if lower.contains("hinge") { return .hinge }
        if lower.contains("bracket") { return .bracket }
        if lower.contains("wedge") { return .wedge }
        if lower.contains("window") || lower.contains("door") { return .window }
        if lower.contains("minifig") { return .minifigure }
        return .brick
    }

    private static func inferColor(from text: String) -> LegoColor {
        let lower = text.lowercased()
        // Try common color names and BrickLink names
        for color in LegoColor.allCases {
            if lower.contains(color.rawValue.lowercased()) { return color }
        }
        if lower.contains("trans") && lower.contains("blue") { return .transparentBlue }
        if lower.contains("trans") && lower.contains("red") { return .transparentRed }
        if lower.contains("trans") || lower.contains("clear") { return .transparent }
        if lower.contains("light blue") || lower.contains("lt. blue") { return .lightBlue }
        if lower.contains("dark blue") || lower.contains("dk. blue") { return .darkBlue }
        if lower.contains("dark red") || lower.contains("dk. red") { return .darkRed }
        if lower.contains("dark green") || lower.contains("dk. green") { return .darkGreen }
        if lower.contains("dark gray") || lower.contains("dark grey") || lower.contains("dk. gray") { return .darkGray }
        if lower.contains("light gray") || lower.contains("light grey") { return .gray }
        if lower.contains("bright") && lower.contains("green") { return .green }
        return .gray
    }

    /// Map BrickLink color ID to LegoColor.
    private static func brickLinkColorToLegoColor(_ colorId: Int) -> LegoColor {
        switch colorId {
        case 1: return .white
        case 2: return .tan
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        case 6: return .green
        case 7: return .blue
        case 8: return .brown
        case 9: return .gray
        case 10: return .darkGray
        case 11: return .black
        case 12: return .transparent
        case 23: return .pink
        case 24: return .purple
        case 34: return .lime
        case 59: return .darkRed
        case 63: return .darkBlue
        case 80: return .darkGreen
        case 105: return .lightBlue
        case 15: return .transparentBlue
        case 17: return .transparentRed
        default: return .gray
        }
    }
}

// MARK: - BrickLink XML Parser

/// Lightweight XML parser for BrickLink Wanted List format.
private class BrickLinkXMLParser: NSObject, XMLParserDelegate {

    struct BrickLinkItem {
        var partNumber: String = ""
        var colorId: Int = 0
        var quantity: Int = 1
        var remarks: String = ""
    }

    private let xml: String
    private var items: [BrickLinkItem] = []
    private var currentItem: BrickLinkItem?
    private var currentElement: String = ""
    private var currentText: String = ""

    init(xml: String) {
        self.xml = xml
    }

    func parse() -> [BrickLinkItem] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "ITEM" {
            currentItem = BrickLinkItem()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentItem != nil else { return }

        switch elementName {
        case "ITEMID":
            currentItem?.partNumber = trimmed
        case "COLOR":
            currentItem?.colorId = Int(trimmed) ?? 0
        case "MINQTY", "QTY":
            currentItem?.quantity = Int(trimmed) ?? 1
        case "REMARKS":
            currentItem?.remarks = trimmed
        case "ITEM":
            if let item = currentItem, !item.partNumber.isEmpty {
                items.append(item)
            }
            currentItem = nil
        default:
            break
        }
    }
}
