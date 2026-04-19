import Foundation
import UIKit

/// Exports an inventory to CSV, PDF, or BrickLink Wanted List XML.
struct InventoryExporter {

    // MARK: - CSV

    /// Generate a CSV string from an inventory.
    static func csv(from inventory: InventoryStore.Inventory) -> String {
        var lines: [String] = []
        lines.append("Part Number,Name,Category,Color,Quantity,Studs Wide,Studs Long,Height Units")
        for p in inventory.pieces.sorted(by: { $0.name < $1.name }) {
            let name = csvEscape(p.name)
            let cat = csvEscape(p.category)
            let color = csvEscape(p.color)
            lines.append("\(p.partNumber),\(name),\(cat),\(color),\(p.quantity),\(p.studsWide),\(p.studsLong),\(p.heightUnits)")
        }
        return lines.joined(separator: "\n")
    }

    /// Write CSV to a temporary file and return its URL.
    static func csvFileURL(from inventory: InventoryStore.Inventory) -> URL? {
        let content = csv(from: inventory)
        let fileName = sanitizeFileName(inventory.name) + ".csv"
        return writeTempFile(named: fileName, content: content)
    }

    // MARK: - BrickLink XML (Wanted List)

    /// Generate BrickLink Wanted List XML from an inventory.
    static func brickLinkXML(from inventory: InventoryStore.Inventory) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<INVENTORY>\n"
        for p in inventory.pieces.sorted(by: { $0.partNumber < $1.partNumber }) {
            xml += "  <ITEM>\n"
            xml += "    <ITEMTYPE>P</ITEMTYPE>\n"
            xml += "    <ITEMID>\(xmlEscape(p.partNumber))</ITEMID>\n"
            xml += "    <COLOR>\(BrickLinkColorMap.id(for: p.pieceColor))</COLOR>\n"
            xml += "    <MINQTY>\(p.quantity)</MINQTY>\n"
            xml += "    <CONDITION>N</CONDITION>\n"
            xml += "    <REMARKS>\(xmlEscape(p.name))</REMARKS>\n"
            xml += "  </ITEM>\n"
        }
        xml += "</INVENTORY>\n"
        return xml
    }

    /// Write BrickLink XML to a temporary file and return its URL.
    static func brickLinkXMLFileURL(from inventory: InventoryStore.Inventory) -> URL? {
        let content = brickLinkXML(from: inventory)
        let fileName = sanitizeFileName(inventory.name) + "_wanted.xml"
        return writeTempFile(named: fileName, content: content)
    }

    // MARK: - PDF

    /// Generate a formatted PDF report of the inventory.
    static func pdfData(from inventory: InventoryStore.Inventory) -> Data {
        let pageWidth: CGFloat = 612 // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        return renderer.pdfData { context in
            var yOffset: CGFloat = 0

            func startNewPage() {
                context.beginPage()
                yOffset = margin
            }

            func ensureSpace(_ needed: CGFloat) {
                if yOffset + needed > pageHeight - margin {
                    startNewPage()
                }
            }

            // Title page
            startNewPage()

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.label
            ]
            let title = inventory.name
            let titleSize = (title as NSString).size(withAttributes: titleAttrs)
            (title as NSString).draw(
                at: CGPoint(x: margin, y: yOffset),
                withAttributes: titleAttrs
            )
            yOffset += titleSize.height + 8

            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let dateStr = inventory.updatedAt.formatted(date: .abbreviated, time: .shortened)
            let subtitle = "\(inventory.totalPieces) pieces · \(inventory.uniquePieces) unique · \(dateStr)"
            (subtitle as NSString).draw(at: CGPoint(x: margin, y: yOffset), withAttributes: subtitleAttrs)
            yOffset += 30

            // Separator
            let separatorPath = UIBezierPath()
            separatorPath.move(to: CGPoint(x: margin, y: yOffset))
            separatorPath.addLine(to: CGPoint(x: margin + contentWidth, y: yOffset))
            UIColor.separator.setStroke()
            separatorPath.lineWidth = 0.5
            separatorPath.stroke()
            yOffset += 16

            // Table header
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: UIColor.label
            ]
            let rowAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.label
            ]

            let columns: [(String, CGFloat, CGFloat)] = [
                ("Part #", margin, 70),
                ("Name", margin + 75, 180),
                ("Category", margin + 260, 90),
                ("Color", margin + 355, 80),
                ("Qty", margin + 440, 40),
                ("Size", margin + 485, 70),
            ]

            func drawHeader() {
                for (label, x, _) in columns {
                    (label as NSString).draw(at: CGPoint(x: x, y: yOffset), withAttributes: headerAttrs)
                }
                yOffset += 16

                let headerLine = UIBezierPath()
                headerLine.move(to: CGPoint(x: margin, y: yOffset))
                headerLine.addLine(to: CGPoint(x: margin + contentWidth, y: yOffset))
                UIColor.separator.setStroke()
                headerLine.lineWidth = 0.5
                headerLine.stroke()
                yOffset += 6
            }

            drawHeader()

            // Rows
            let sorted = inventory.pieces.sorted { $0.category < $1.category || ($0.category == $1.category && $0.name < $1.name) }

            for piece in sorted {
                ensureSpace(18)
                if yOffset == margin {
                    drawHeader()
                }

                let sizeStr = "\(piece.studsWide)×\(piece.studsLong)×\(piece.heightUnits)"
                let rowData = [
                    piece.partNumber,
                    piece.name,
                    piece.category,
                    piece.color,
                    "\(piece.quantity)",
                    sizeStr
                ]
                for (i, text) in rowData.enumerated() {
                    let (_, x, maxW) = columns[i]
                    let truncated = truncateText(text, maxWidth: maxW, attributes: rowAttrs)
                    (truncated as NSString).draw(at: CGPoint(x: x, y: yOffset), withAttributes: rowAttrs)
                }
                yOffset += 16
            }

            // Footer with page summary
            ensureSpace(40)
            yOffset += 10
            let footerLine = UIBezierPath()
            footerLine.move(to: CGPoint(x: margin, y: yOffset))
            footerLine.addLine(to: CGPoint(x: margin + contentWidth, y: yOffset))
            UIColor.separator.setStroke()
            footerLine.lineWidth = 0.5
            footerLine.stroke()
            yOffset += 8

            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let footer = "Generated by \(AppConfig.appName) · \(Date().formatted(date: .abbreviated, time: .shortened))"
            (footer as NSString).draw(at: CGPoint(x: margin, y: yOffset), withAttributes: footerAttrs)
        }
    }

    /// Write PDF to a temporary file and return its URL.
    static func pdfFileURL(from inventory: InventoryStore.Inventory) -> URL? {
        let data = pdfData(from: inventory)
        let fileName = sanitizeFileName(inventory.name) + ".pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private static func csvEscape(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return text
    }

    private static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func sanitizeFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        return String(name.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func writeTempFile(named fileName: String, content: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func truncateText(_ text: String, maxWidth: CGFloat, attributes: [NSAttributedString.Key: Any]) -> String {
        let size = (text as NSString).size(withAttributes: attributes)
        if size.width <= maxWidth { return text }
        var truncated = text
        while truncated.count > 1 {
            truncated = String(truncated.dropLast())
            let newSize = ((truncated + "…") as NSString).size(withAttributes: attributes)
            if newSize.width <= maxWidth { return truncated + "…" }
        }
        return "…"
    }

    /// Map LegoColor to approximate BrickLink color IDs.
    /// Delegates to `BrickLinkColorMap` (kept for backwards-compatible call sites).
    static func brickLinkColorId(for color: LegoColor) -> Int {
        BrickLinkColorMap.id(for: color)
    }
}
