import UIKit
import Photos
import PhotosUI
import SnapKit

final class PhotoViewerViewModel {
    let photo: PhotoItem
    let album: Album
    private let storage: AssetStorage
    private let photoLibrary: PhotoLibraryService
    private let nearby: NearbySessionService

    init(
        photo: PhotoItem,
        album: Album,
        storage: AssetStorage,
        photoLibrary: PhotoLibraryService,
        nearby: NearbySessionService
    ) {
        self.photo = photo
        self.album = album
        self.storage = storage
        self.photoLibrary = photoLibrary
        self.nearby = nearby
    }

    var image: UIImage? {
        storage.image(at: photo.photoResourcePath) ?? storage.image(at: photo.thumbnailPath)
    }

    var hasOriginal: Bool {
        photo.assetState == .originalAvailable && storage.absoluteURL(for: photo.photoResourcePath) != nil
    }

    func requestLivePhoto(completion: @escaping (PHLivePhoto?) -> Void) {
        guard photo.isLivePhoto,
              let imageURL = storage.absoluteURL(for: photo.photoResourcePath),
              let videoURL = storage.absoluteURL(for: photo.pairedVideoPath),
              let placeholder = image else {
            completion(nil)
            return
        }
        PHLivePhoto.request(
            withResourceFileURLs: [imageURL, videoURL],
            placeholderImage: placeholder,
            targetSize: .zero,
            contentMode: .aspectFit
        ) { livePhoto, _ in completion(livePhoto) }
    }

    func save(completion: @escaping (Bool) -> Void) {
        photoLibrary.saveToPhotos(photo: photo, storage: storage, completion: completion)
    }

    func downloadOriginal() {
        nearby.requestOriginal(photoID: photo.id)
    }
}

final class PhotoViewerViewController: UIViewController, UIScrollViewDelegate {
    private let viewModel: PhotoViewerViewModel
    private let storage: AssetStorage
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let livePhotoView = PHLivePhotoView()
    private let missingLabel = UILabel()

    init(viewModel: PhotoViewerViewModel, storage: AssetStorage) {
        self.viewModel = viewModel
        self.storage = storage
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.largeTitleDisplayMode = .never
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        imageView.contentMode = .scaleAspectFit
        imageView.image = viewModel.image
        livePhotoView.contentMode = .scaleAspectFit
        livePhotoView.isHidden = true
        missingLabel.text = L10n.text("photo.originalNotDownloaded")
        missingLabel.textColor = .white
        missingLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        missingLabel.textAlignment = .center
        missingLabel.isHidden = viewModel.hasOriginal
        scrollView.addSubview(imageView)
        view.addSubviews(scrollView, livePhotoView, missingLabel)
        scrollView.snp.makeConstraints { $0.edges.equalToSuperview() }
        imageView.snp.makeConstraints { $0.edges.equalTo(scrollView.frameLayoutGuide) }
        livePhotoView.snp.makeConstraints { $0.edges.equalToSuperview() }
        missingLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(AppSpacing.xLarge)
            make.height.equalTo(44)
        }
        configureToolbar()
        if viewModel.photo.isLivePhoto && viewModel.hasOriginal {
            viewModel.requestLivePhoto { [weak self] livePhoto in
                guard let self, let livePhoto else { return }
                self.livePhotoView.livePhoto = livePhoto
                self.livePhotoView.isHidden = false
                self.scrollView.isHidden = true
                self.livePhotoView.startPlayback(with: .hint)
            }
        }
    }

    private func configureToolbar() {
        let info = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            style: .plain,
            target: self,
            action: #selector(infoTapped)
        )
        let download = UIBarButtonItem(
            image: UIImage(systemName: "arrow.down.circle"),
            style: .plain,
            target: self,
            action: #selector(downloadTapped)
        )
        download.isEnabled = !viewModel.hasOriginal && viewModel.album.connectionState == .connected
        let save = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.down"),
            style: .plain,
            target: self,
            action: #selector(saveTapped)
        )
        save.isEnabled = viewModel.hasOriginal
        toolbarItems = [info, .flexibleSpace(), download, .flexibleSpace(), save]
        navigationController?.setToolbarHidden(false, animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: true)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    @objc private func infoTapped() {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let date = viewModel.photo.capturedAt.map(formatter.string) ?? L10n.text("photo.unknown")
        let size = ByteCountFormatter.string(fromByteCount: viewModel.photo.byteCount, countStyle: .file)
        let location: String
        if let latitude = viewModel.photo.latitude, let longitude = viewModel.photo.longitude {
            location = String(format: "%.5f, %.5f", latitude, longitude)
        } else {
            location = L10n.text("photo.unknown")
        }
        let message = L10n.text(
            "photo.info.format",
            viewModel.photo.contributorName,
            date,
            location,
            L10n.text(viewModel.photo.isLivePhoto ? "photo.type.live" : "photo.type.still"),
            viewModel.photo.pixelWidth,
            viewModel.photo.pixelHeight,
            size,
            viewModel.photo.assetState.rawValue
        )
        let alert = UIAlertController(title: L10n.text("photo.info"), message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: L10n.text("common.done"), style: .cancel))
        present(alert, animated: true)
    }

    @objc private func downloadTapped() {
        viewModel.downloadOriginal()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @objc private func saveTapped() {
        viewModel.save { success in
            UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        }
    }
}
