import UIKit

extension UIImage {
    /// Return a copy of the image with `.up` orientation by redrawing the
    /// pixel data so EXIF orientation is baked into the bitmap.
    ///
    /// This is essential before passing a UIImage to any Vision/CoreImage
    /// pipeline that calls `.cgImage`, because `cgImage` returns the raw
    /// bitmap without applying the orientation hint — meaning saliency,
    /// feature prints, and color extraction will all "see" the image
    /// rotated incorrectly.
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
