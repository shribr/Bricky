import Foundation
import UIKit

/// Persists user-captured reference photos for custom catalog figures.
/// Each image is stored as a JPEG in `Documents/UserFigureImages/` so
/// it survives app updates, and is exposed to the rest of the app via
/// a stable `file://` URL that `MinifigureImageView` and the
/// identification pipeline can load like any other reference image.
final class UserFigureImageStorage {
    static let shared = UserFigureImageStorage()

    private let folderURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folderURL = docs.appendingPathComponent("UserFigureImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    /// Write a user-captured photo for the given figure id and return
    /// a stable `file://` URL the catalog can persist as `imgURL`.
    /// Returns nil if the image couldn't be encoded.
    @discardableResult
    func save(_ image: UIImage, for figureId: String) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let path = folderURL.appendingPathComponent("\(figureId).jpg")
        do {
            try data.write(to: path, options: .atomic)
            return path
        } catch {
            return nil
        }
    }

    /// Load a previously-saved user image.
    func image(for figureId: String) -> UIImage? {
        let path = folderURL.appendingPathComponent("\(figureId).jpg")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return UIImage(data: data)
    }

    /// Remove the stored image when a user figure is deleted.
    func remove(figureId: String) {
        let path = folderURL.appendingPathComponent("\(figureId).jpg")
        try? FileManager.default.removeItem(at: path)
    }

    /// The on-disk directory (used by the catalog import path).
    var directoryURL: URL { folderURL }
}
