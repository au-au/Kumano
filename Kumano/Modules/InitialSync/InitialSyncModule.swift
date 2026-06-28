import UIKit
import SnapKit

final class InitialSyncViewModel: NearbySessionServiceDelegate {
    var onProgress: ((Float, String) -> Void)?
    var onComplete: ((Album) -> Void)?
    var onError: ((String) -> Void)?
    private let nearby: NearbySessionService
    private let repository: AppRepository
    private let storage: AssetStorage
    private var syncedAlbum: Album?
    private var pendingThumbnails: [UUID: URL] = [:]

    init(nearby: NearbySessionService, repository: AppRepository, storage: AssetStorage) {
        self.nearby = nearby
        self.repository = repository
        self.storage = storage
    }

    func start() {
        nearby.delegate = self
        onProgress?(0.2, L10n.text("sync.connecting"))
    }

    func cancel() {
        nearby.stop()
    }

    func nearbyService(_ service: NearbySessionService, didReceive event: NearbyEvent) {
        switch event {
        case .stateChanged(.connected):
            onProgress?(0.4, L10n.text("sync.details"))
        case .albumReceived(var album):
            album.localRole = .participant
            album.connectionState = .connected
            album.updatedAt = Date()
            album.photos = album.photos.map { $0.remoteMetadataCopy() }
            applyPendingThumbnails(to: &album)
            syncedAlbum = album
            repository.saveAlbum(album)
            onProgress?(1, L10n.text("sync.ready"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.onComplete?(album) }
        case .resourceReceived(let photoID, let kind, let url):
            guard kind == .thumbnail else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            guard var album = syncedAlbum else {
                pendingThumbnails[photoID] = url
                return
            }
            storeThumbnail(from: url, photoID: photoID, in: &album)
            syncedAlbum = album
            repository.saveAlbum(album)
        case .error(let message):
            onError?(message)
        default:
            break
        }
    }

    private func applyPendingThumbnails(to album: inout Album) {
        for (photoID, url) in pendingThumbnails {
            storeThumbnail(from: url, photoID: photoID, in: &album)
        }
        pendingThumbnails.removeAll()
    }

    private func storeThumbnail(from url: URL, photoID: UUID, in album: inout Album) {
        guard let index = album.photos.firstIndex(where: { $0.id == photoID }) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            album.photos[index].thumbnailPath = try storage.storeResource(
                from: url,
                albumID: album.id,
                photoID: photoID,
                filename: "thumbnail.jpg"
            )
            try? FileManager.default.removeItem(at: url)
        } catch {
            onError?(error.localizedDescription)
        }
    }
}

final class InitialSyncViewController: BaseViewController {
    var onComplete: ((Album) -> Void)?
    private let viewModel: InitialSyncViewModel
    private let progress = UIProgressView(progressViewStyle: .default)
    private let statusLabel = UILabel()

    init(viewModel: InitialSyncViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("sync.title")
        navigationItem.hidesBackButton = true
        let icon = UIImageView(image: UIImage(systemName: "photo.stack"))
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .label
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        let cancel = AppDesignSystem.button(title: L10n.text("common.cancel"), style: .secondary)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [icon, statusLabel, progress, cancel])
        stack.axis = .vertical
        stack.spacing = AppSpacing.xLarge
        view.addSubview(stack)
        icon.snp.makeConstraints { $0.height.equalTo(72) }
        stack.snp.makeConstraints { make in
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(AppSpacing.xLarge)
            make.centerY.equalTo(view.safeAreaLayoutGuide)
        }
        viewModel.onProgress = { [weak self] value, text in
            self?.progress.setProgress(value, animated: true)
            self?.statusLabel.text = text
        }
        viewModel.onComplete = { [weak self] album in self?.onComplete?(album) }
        viewModel.onError = { [weak self] message in self?.statusLabel.text = message }
        viewModel.start()
    }

    @objc private func cancelTapped() {
        viewModel.cancel()
        navigationController?.popViewController(animated: true)
    }
}
