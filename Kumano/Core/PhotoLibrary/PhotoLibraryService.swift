import UIKit
import Photos
import PhotosUI

protocol PhotoLibraryService: AnyObject {
    func presentPicker(
        from viewController: UIViewController,
        albumID: UUID,
        contributor: UserProfile,
        completion: @escaping (Result<[PhotoItem], Error>) -> Void
    )
    func saveToPhotos(photo: PhotoItem, storage: AssetStorage, completion: @escaping (Bool) -> Void)
}

final class SystemPhotoLibraryService: NSObject, PhotoLibraryService {
    private let storage: AssetStorage
    private var coordinators: [UUID: PickerCoordinator] = [:]

    init(storage: AssetStorage) {
        self.storage = storage
    }

    func presentPicker(
        from viewController: UIViewController,
        albumID: UUID,
        contributor: UserProfile,
        completion: @escaping (Result<[PhotoItem], Error>) -> Void
    ) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized || status == .limited else {
                    completion(.failure(PhotoImportError.permissionDenied))
                    return
                }
                var configuration = PHPickerConfiguration(photoLibrary: .shared())
                configuration.filter = .any(of: [.images, .livePhotos])
                configuration.selectionLimit = 0
                configuration.preferredAssetRepresentationMode = .current
                let picker = PHPickerViewController(configuration: configuration)
                let id = UUID()
                let coordinator = PickerCoordinator(
                    id: id,
                    albumID: albumID,
                    contributor: contributor,
                    storage: self.storage
                ) { [weak self] result in
                    self?.coordinators[id] = nil
                    completion(result)
                }
                self.coordinators[id] = coordinator
                picker.delegate = coordinator
                viewController.present(picker, animated: true)
            }
        }
    }

    func saveToPhotos(photo: PhotoItem, storage: AssetStorage, completion: @escaping (Bool) -> Void) {
        guard let photoURL = storage.absoluteURL(for: photo.photoResourcePath) else {
            completion(false)
            return
        }
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: photoURL, options: nil)
            if let videoURL = storage.absoluteURL(for: photo.pairedVideoPath) {
                request.addResource(with: .pairedVideo, fileURL: videoURL, options: nil)
            }
        } completionHandler: { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }
}

private enum PhotoImportError: Error {
    case permissionDenied
    case missingAsset
    case incompleteLivePhoto
}

private final class PickerCoordinator: NSObject, PHPickerViewControllerDelegate {
    let id: UUID
    private let albumID: UUID
    private let contributor: UserProfile
    private let storage: AssetStorage
    private let completion: (Result<[PhotoItem], Error>) -> Void

    init(
        id: UUID,
        albumID: UUID,
        contributor: UserProfile,
        storage: AssetStorage,
        completion: @escaping (Result<[PhotoItem], Error>) -> Void
    ) {
        self.id = id
        self.albumID = albumID
        self.contributor = contributor
        self.storage = storage
        self.completion = completion
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else {
            completion(.success([]))
            return
        }
        let identifiers = results.compactMap(\.assetIdentifier)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assetByID: [String: PHAsset] = [:]
        assets.enumerateObjects { asset, _, _ in assetByID[asset.localIdentifier] = asset }

        let group = DispatchGroup()
        let lock = NSLock()
        var imported: [PhotoItem] = []
        var firstError: Error?

        for result in results {
            guard let identifier = result.assetIdentifier, let asset = assetByID[identifier] else {
                firstError = PhotoImportError.missingAsset
                continue
            }
            group.enter()
            importAsset(asset) { result in
                lock.lock()
                switch result {
                case .success(let photo): imported.append(photo)
                case .failure(let error): firstError = firstError ?? error
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if imported.isEmpty, let firstError {
                self.completion(.failure(firstError))
            } else {
                self.completion(.success(imported.sorted { ($0.capturedAt ?? $0.importedAt) < ($1.capturedAt ?? $1.importedAt) }))
            }
        }
    }

    private func importAsset(_ asset: PHAsset, completion: @escaping (Result<PhotoItem, Error>) -> Void) {
        let photoID = UUID()
        let resources = PHAssetResource.assetResources(for: asset)
        let imageResource = resources.first { $0.type == .fullSizePhoto }
            ?? resources.first { $0.type == .photo }
        let videoResource = resources.first { $0.type == .fullSizePairedVideo }
            ?? resources.first { $0.type == .pairedVideo }
        let isLive = asset.mediaSubtypes.contains(.photoLive)
        guard let imageResource, !isLive || videoResource != nil else {
            completion(.failure(PhotoImportError.incompleteLivePhoto))
            return
        }

        do {
            let directory = try storage.assetDirectory(albumID: albumID, photoID: photoID)
            let imageURL = directory.appendingPathComponent("original-\(imageResource.originalFilename)")
            let videoURL = videoResource.map { directory.appendingPathComponent("paired-\($0.originalFilename)") }
            let group = DispatchGroup()
            var writeError: Error?

            group.enter()
            PHAssetResourceManager.default().writeData(for: imageResource, toFile: imageURL, options: nil) { error in
                writeError = error
                group.leave()
            }
            if let videoResource, let videoURL {
                group.enter()
                PHAssetResourceManager.default().writeData(for: videoResource, toFile: videoURL, options: nil) { error in
                    writeError = writeError ?? error
                    group.leave()
                }
            }

            requestThumbnail(asset) { thumbnail in
                group.notify(queue: .global(qos: .userInitiated)) {
                    if let writeError {
                        completion(.failure(writeError))
                        return
                    }
                    let thumbnailPath = try? thumbnail.flatMap {
                        try self.storage.storeThumbnail($0, albumID: self.albumID, photoID: photoID)
                    }
                    let root = self.storage.absoluteURL(for: "")!
                    let relative: (URL) -> String = {
                        $0.path.replacingOccurrences(of: root.path + "/", with: "")
                    }
                    let imageSize = (try? imageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    let videoSize = videoURL.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.map(Int64.init) ?? 0
                    let item = PhotoItem(
                        id: photoID,
                        albumID: self.albumID,
                        contributorID: self.contributor.memberID,
                        contributorName: self.contributor.displayName,
                        capturedAt: asset.creationDate,
                        importedAt: Date(),
                        latitude: asset.location?.coordinate.latitude,
                        longitude: asset.location?.coordinate.longitude,
                        isLivePhoto: isLive,
                        pixelWidth: asset.pixelWidth,
                        pixelHeight: asset.pixelHeight,
                        byteCount: imageSize + videoSize,
                        thumbnailPath: thumbnailPath ?? nil,
                        photoResourcePath: relative(imageURL),
                        pairedVideoPath: videoURL.map(relative),
                        assetState: .originalAvailable,
                        contentHash: "\(imageResource.assetLocalIdentifier)-\(imageSize)-\(videoSize)"
                    )
                    completion(.success(item))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    private func requestThumbnail(_ asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 600, height: 600),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in completion(image) }
    }
}
