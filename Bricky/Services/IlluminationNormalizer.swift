import CoreGraphics

/// Per-channel white-balance gains from a gray-world illuminant estimate.
struct WhiteBalanceGains: Equatable {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat

    static let identity = WhiteBalanceGains(r: 1, g: 1, b: 1)

    var isIdentity: Bool { r == 1 && g == 1 && b == 1 }
}

/// Gray-world white balance so a colored light cast (warm bulbs, blue shade)
/// doesn't shift a brick's classified LEGO color.
///
/// The illuminant is estimated from the WHOLE frame — never a single brick crop —
/// so a uniformly colored brick is not desaturated toward gray. The same gains
/// are then applied to every crop before HSL color classification.
enum IlluminationNormalizer {
    /// Clamp on any single channel gain, so a scene that genuinely is mostly one
    /// color can't drive a wild correction.
    static let minGain: CGFloat = 0.6
    static let maxGain: CGFloat = 1.8

    /// Estimate gray-world gains from a downsampled copy of the full image.
    static func estimateGrayWorldGains(from cgImage: CGImage, sampleDimension: Int = 32) -> WhiteBalanceGains {
        let n = max(2, sampleDimension)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: n, height: n,
            bitsPerComponent: 8,
            bytesPerRow: n * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .identity }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: n, height: n))

        var sumR: CGFloat = 0, sumG: CGFloat = 0, sumB: CGFloat = 0
        let count = CGFloat(n * n)
        for i in 0..<(n * n) {
            let o = i * 4
            sumR += CGFloat(pixels[o])
            sumG += CGFloat(pixels[o + 1])
            sumB += CGFloat(pixels[o + 2])
        }
        return gains(meanR: sumR / count, meanG: sumG / count, meanB: sumB / count)
    }

    /// Pure gray-world gain computation. Means may be 0–255 or 0–1 — only ratios
    /// matter. Gains normalize each channel toward the overall gray mean and are
    /// clamped to `[minGain, maxGain]`.
    static func gains(meanR: CGFloat, meanG: CGFloat, meanB: CGFloat) -> WhiteBalanceGains {
        let meanGray = (meanR + meanG + meanB) / 3
        guard meanGray > 0.0001 else { return .identity }
        func gain(_ mean: CGFloat) -> CGFloat {
            guard mean > 0.0001 else { return 1 }
            return min(maxGain, max(minGain, meanGray / mean))
        }
        return WhiteBalanceGains(r: gain(meanR), g: gain(meanG), b: gain(meanB))
    }

    /// Apply gains to a normalized (0–1) RGB triple, clamped back to 0–1.
    static func apply(_ gains: WhiteBalanceGains, r: CGFloat, g: CGFloat, b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        (
            min(1, max(0, r * gains.r)),
            min(1, max(0, g * gains.g)),
            min(1, max(0, b * gains.b))
        )
    }
}
