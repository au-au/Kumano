import UIKit

protocol AssetStorage: AnyObject {
    func assetDirectory(albumID: UUID, photoID: UUID) throws -> URL
    func storeThumbnail(_ image: UIImage, albumID: UUID, photoID: UUID) throws -> String
    func storeResource(from sourceURL: URL, albumID: UUID, photoID: UUID, filename: String) throws -> String
    func image(at relativePath: String?) -> UIImage?
    func absoluteURL(for relativePath: String?) -> URL?
}

final class LocalAssetStorage: AssetStorage {
    private let root: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kumano/Assets", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func assetDirectory(albumID: UUID, photoID: UUID) throws -> URL {
        let url = root
            .appendingPathComponent(albumID.uuidString, isDirectory: true)
            .appendingPathComponent(photoID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func storeThumbnail(_ image: UIImage, albumID: UUID, photoID: UUID) throws -> String {
        let directory = try assetDirectory(albumID: albumID, photoID: photoID)
        let url = directory.appendingPathComponent("thumbnail.jpg")
        guard let data = image.jpegData(compressionQuality: 0.72) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return relativePath(for: url)
    }

    func storeResource(from sourceURL: URL, albumID: UUID, photoID: UUID, filename: String) throws -> String {
        let directory = try assetDirectory(albumID: albumID, photoID: photoID)
        let destination = directory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return relativePath(for: destination)
    }

    func image(at relativePath: String?) -> UIImage? {
        guard let url = absoluteURL(for: relativePath) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    func absoluteURL(for relativePath: String?) -> URL? {
        guard let relativePath else { return nil }
        return root.appendingPathComponent(relativePath)
    }

    func relativePath(for url: URL) -> String {
        url.path.replacingOccurrences(of: root.path + "/", with: "")
    }
}
