import UIKit

/// Generates 2D piece preview images programmatically based on piece category and color.
/// Used in catalog views and piece lists when no photographic image is available.
final class PieceImageGenerator {
    static let shared = PieceImageGenerator()

    private var cache: [String: UIImage] = [:]
    private let cacheQueue = DispatchQueue(label: AppConfig.pieceImageQueue)

    private init() {}

    /// Generate or retrieve cached piece image
    func image(for piece: LegoPiece, size: CGFloat = 64) -> UIImage {
        let key = "\(piece.category.rawValue)-\(piece.color.rawValue)-\(piece.dimensions.studsWide)x\(piece.dimensions.studsLong)-\(Int(size))"
        if let cached = cache[key] { return cached }

        let image = render(category: piece.category, color: piece.color,
                           studsWide: piece.dimensions.studsWide,
                           studsLong: piece.dimensions.studsLong, size: size)
        cacheQueue.async { self.cache[key] = image }
        return image
    }

    /// Generate image for a category/color combination
    func image(category: PieceCategory, color: LegoColor, size: CGFloat = 64) -> UIImage {
        let key = "\(category.rawValue)-\(color.rawValue)-\(Int(size))"
        if let cached = cache[key] { return cached }

        let image = render(category: category, color: color, studsWide: 2, studsLong: 4, size: size)
        cacheQueue.async { self.cache[key] = image }
        return image
    }

    /// Clear the image cache
    func clearCache() {
        cacheQueue.async { self.cache.removeAll() }
    }

    // MARK: - Rendering

    private func render(category: PieceCategory, color: LegoColor, studsWide: Int, studsLong: Int, size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let fillColor = UIColor(hex: color.hex)
        let darkColor = fillColor.darker(by: 0.2)
        let lightColor = fillColor.lighter(by: 0.15)

        return renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let inset = size * 0.1
            let drawRect = rect.insetBy(dx: inset, dy: inset)

            switch category {
            case .brick:
                drawBrick(in: drawRect, ctx: context, fill: fillColor, dark: darkColor, light: lightColor, studsWide: studsWide, studsLong: studsLong, size: size)
            case .plate:
                drawPlate(in: drawRect, ctx: context, fill: fillColor, dark: darkColor, light: lightColor, studsWide: studsWide, studsLong: studsLong, size: size)
            case .tile:
                drawTile(in: drawRect, ctx: context, fill: fillColor, dark: darkColor, size: size)
            case .slope:
                drawSlope(in: drawRect, ctx: context, fill: fillColor, dark: darkColor, light: lightColor, size: size)
            case .round:
                drawRound(in: drawRect, ctx: context, fill: fillColor, dark: darkColor, light: lightColor, size: size)
            case .arch:
                drawArch(in: drawRect, ctx: context, fill: fillColor, dark: darkColor, size: size)
            case .technic:
                drawTechnic(in: drawRect, ctx: context, fill: fillColor, dark: darkColor, light: lightColor, size: size)
            case .wheel:
                drawWheel(in: drawRect, ctx: context, fill: fillColor, size: size)
            case .minifigure:
                drawMinifigure(in: drawRect, ctx: context, fill: fillColor, size: size)
            default:
                drawBrick(in: drawRect, ctx: context, fill: fillColor, dark: darkColor, light: lightColor, studsWide: min(studsWide, 4), studsLong: min(studsLong, 4), size: size)
            }
        }
    }

    // MARK: - Shape Renderers

    private func drawBrick(in rect: CGRect, ctx: UIGraphicsImageRendererContext, fill: UIColor, dark: UIColor, light: UIColor, studsWide: Int, studsLong: Int, size: CGFloat) {
        let brickH = rect.height * 0.55
        let brickY = rect.maxY - brickH
        let brickRect = CGRect(x: rect.minX, y: brickY, width: rect.width, height: brickH)

        // Body
        let body = UIBezierPath(roundedRect: brickRect, cornerRadius: size * 0.02)
        fill.setFill()
        body.fill()

        // Top highlight
        let topRect = CGRect(x: brickRect.minX, y: brickRect.minY, width: brickRect.width, height: brickH * 0.12)
        light.setFill()
        UIBezierPath(rect: topRect).fill()

        // Bottom shadow
        let botRect = CGRect(x: brickRect.minX, y: brickRect.maxY - brickH * 0.12, width: brickRect.width, height: brickH * 0.12)
        dark.setFill()
        UIBezierPath(rect: botRect).fill()

        // Studs
        let cols = min(studsWide, 4)
        let rows = min(studsLong, 2)
        let studR = min(size * 0.06, rect.width / CGFloat(cols * 3))
        let spacingX = rect.width / CGFloat(cols + 1)
        let spacingY = (brickY - rect.minY - studR) / CGFloat(rows + 1)
        let studsBaseY = rect.minY + studR

        for r in 0..<rows {
            for c in 0..<cols {
                let cx = rect.minX + spacingX * CGFloat(c + 1)
                let cy = studsBaseY + spacingY * CGFloat(r + 1)
                let studPath = UIBezierPath(ovalIn: CGRect(x: cx - studR, y: cy - studR, width: studR * 2, height: studR * 2))
                light.setFill()
                studPath.fill()
                let innerR = studR * 0.6
                let innerPath = UIBezierPath(ovalIn: CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2))
                fill.setFill()
                innerPath.fill()
            }
        }
    }

    private func drawPlate(in rect: CGRect, ctx: UIGraphicsImageRendererContext, fill: UIColor, dark: UIColor, light: UIColor, studsWide: Int, studsLong: Int, size: CGFloat) {
        let plateH = rect.height * 0.25
        let plateY = rect.maxY - plateH
        let plateRect = CGRect(x: rect.minX, y: plateY, width: rect.width, height: plateH)

        fill.setFill()
        UIBezierPath(roundedRect: plateRect, cornerRadius: size * 0.015).fill()
        dark.setFill()
        UIBezierPath(rect: CGRect(x: plateRect.minX, y: plateRect.maxY - plateH * 0.15, width: plateRect.width, height: plateH * 0.15)).fill()

        // Studs on top
        let cols = min(studsWide, 4)
        let studR = min(size * 0.055, rect.width / CGFloat(cols * 3))
        let spacingX = rect.width / CGFloat(cols + 1)
        let studY = plateY - studR * 1.5

        for c in 0..<cols {
            let cx = rect.minX + spacingX * CGFloat(c + 1)
            let studPath = UIBezierPath(ovalIn: CGRect(x: cx - studR, y: studY - studR, width: studR * 2, height: studR * 2))
            light.setFill()
            studPath.fill()
        }
    }

    private func drawTile(in rect: CGRect, ctx: UIGraphicsImageRendererContext, fill: UIColor, dark: UIColor, size: CGFloat) {
        let tileH = rect.height * 0.22
        let tileY = rect.maxY - tileH
        let tileRect = CGRect(x: rect.minX, y: tileY, width: rect.width, height: tileH)

        fill.setFill()
        UIBezierPath(roundedRect: tileRect, cornerRadius: size * 0.02).fill()

        // Subtle shine line
        UIColor.white.withAlphaComponent(0.3).setFill()
        let shineRect = CGRect(x: tileRect.minX + tileRect.width * 0.15, y: tileRect.minY + 2,
                                width: tileRect.width * 0.5, height: 2)
        UIBezierPath(roundedRect: shineRect, cornerRadius: 1).fill()
    }

    private func drawSlope(in rect: CGRect, ctx: UIGraphicsImageRendererContext, fill: UIColor, dark: UIColor, light: UIColor, size: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.5))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.15))
        path.close()
        fill.setFill()
        path.fill()

        // Top edge highlight
        let highlight = UIBezierPath()
        highlight.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.15))
        highlight.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.5))
        highlight.lineWidth = size * 0.02
        light.setStroke()
        highlight.stroke()
    }

    private func drawRound(in rect: CGRect, ctx: UIGraphicsImageRendererContext, fill: UIColor, dark: UIColor, light: UIColor, size: CGFloat) {
        let r = min(rect.width, rect.height) * 0.4
        let center = CGPoint(x: rect.midX, y: rect.midY + r * 0.15)

        // Cylinder body
        let bodyRect = CGRect(x: center.x - r, y: center.y - r * 0.3, width: r * 2, height: r * 1.3)
        dark.setFill()
        UIBezierPath(roundedRect: bodyRect, cornerRadius: r * 0.3).fill()

        // Top circle
        let topOval = CGRect(x: center.x - r, y: center.y - r * 0.8, width: r * 2, height: r)
        fill.setFill()
        UIBezierPath(ovalIn: topOval).fill()

        // Stud on top
        let studR = r * 0.35
        let studOval = CGRect(x: center.x - studR, y: center.y - r * 0.55, width: studR * 2, height: studR * 0.8)
        light.setFill()
        UIBezierPath(ovalIn: studOval).fill()
    }

    private func drawArch(in rect: CGRect, ctx: UIGraphicsImageRendererContext, fill: UIColor, dark: UIColor, size: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                      controlPoint1: CGPoint(x: rect.minX, y: rect.minY),
                      controlPoint2: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        // Cut out the inner arch
        let innerInset = rect.width * 0.2
        let innerRect = rect.insetBy(dx: innerInset, dy: 0)
        let innerPath = UIBezierPath()
        innerPath.move(to: CGPoint(x: innerRect.minX, y: rect.maxY))
        innerPath.addLine(to: CGPoint(x: innerRect.minX, y: rect.midY + rect.height * 0.15))
        innerPath.addCurve(to: CGPoint(x: innerRect.maxX, y: rect.midY + rect.height * 0.15),
                           controlPoint1: CGPoint(x: innerRect.minX, y: rect.midY - rect.height * 0.1),
                           controlPoint2: CGPoint(x: innerRect.maxX, y: rect.midY - rect.height * 0.1))
        innerPath.addLine(to: CGPoint(x: innerRect.maxX, y: rect.maxY))
        innerPath.close()

        path.close()
        fill.setFill()
        path.fill()

        UIColor.black.withAlphaComponent(0.3).setFill()
        innerPath.fill()
    }

    private func drawTechnic(in rect: CGRect, ctx: UIGraphicsImageRendererContext, fill: UIColor, dark: UIColor, light: UIColor, size: CGFloat) {
        // Technic beam with holes
        let beamH = rect.height * 0.30
        let beamY = rect.midY - beamH / 2
        let beamRect = CGRect(x: rect.minX, y: beamY, width: rect.width, height: beamH)

        fill.setFill()
        UIBezierPath(roundedRect: beamRect, cornerRadius: beamH * 0.3).fill()

        // Holes
        let holeCount = 3
        let spacing = beamRect.width / CGFloat(holeCount + 1)
        let holeR = beamH * 0.25
        for i in 1...holeCount {
            let cx = beamRect.minX + spacing * CGFloat(i)
            let holeOval = CGRect(x: cx - holeR, y: beamRect.midY - holeR, width: holeR * 2, height: holeR * 2)
            dark.setFill()
            UIBezierPath(ovalIn: holeOval).fill()
            let innerR = holeR * 0.6
            UIColor.black.withAlphaComponent(0.3).setFill()
            UIBezierPath(ovalIn: CGRect(x: cx - innerR, y: beamRect.midY - innerR, width: innerR * 2, height: innerR * 2)).fill()
        }
    }

    private func drawWheel(in rect: CGRect, ctx: UIGraphicsImageRendererContext, fill: UIColor, size: CGFloat) {
        let r = min(rect.width, rect.height) * 0.4
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Tire (dark gray outer ring)
        UIColor.darkGray.setFill()
        UIBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)).fill()

        // Hub
        let hubR = r * 0.55
        fill.setFill()
        UIBezierPath(ovalIn: CGRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2)).fill()

        // Axle hole
        let axleR = r * 0.15
        UIColor.black.withAlphaComponent(0.4).setFill()
        UIBezierPath(ovalIn: CGRect(x: center.x - axleR, y: center.y - axleR, width: axleR * 2, height: axleR * 2)).fill()
    }

    private func drawMinifigure(in rect: CGRect, ctx: UIGraphicsImageRendererContext, fill: UIColor, size: CGFloat) {
        let headR = rect.width * 0.15
        let headCenter = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.2)

        // Head (yellow)
        UIColor(red: 0.96, green: 0.80, blue: 0.18, alpha: 1.0).setFill()
        UIBezierPath(ovalIn: CGRect(x: headCenter.x - headR, y: headCenter.y - headR, width: headR * 2, height: headR * 2)).fill()

        // Torso
        let torsoRect = CGRect(x: rect.midX - rect.width * 0.22, y: headCenter.y + headR,
                                width: rect.width * 0.44, height: rect.height * 0.3)
        fill.setFill()
        UIBezierPath(roundedRect: torsoRect, cornerRadius: size * 0.01).fill()

        // Legs
        let legW = rect.width * 0.18
        let legH = rect.height * 0.3
        let legY = torsoRect.maxY
        fill.setFill()
        UIBezierPath(rect: CGRect(x: rect.midX - legW - 1, y: legY, width: legW, height: legH)).fill()
        UIBezierPath(rect: CGRect(x: rect.midX + 1, y: legY, width: legW, height: legH)).fill()
    }
}

// MARK: - UIColor Helpers

private extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    func darker(by percentage: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: max(b - percentage, 0), alpha: a)
    }

    func lighter(by percentage: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: max(s - percentage * 0.3, 0), brightness: min(b + percentage, 1), alpha: a)
    }
}
