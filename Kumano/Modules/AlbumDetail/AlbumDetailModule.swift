import UIKit
import PhotosUI
import SnapKit

struct PhotoSection {
    let title: String
    let photos: [PhotoItem]
}

final class AlbumDetailViewModel: NearbySessionServiceDelegate {
    var onUpdate: (() -> Void)?
    var onError: ((String) -> Void)?
    var onImporting: ((Bool) -> Void)?

    private(set) var album: Album
    private let profile: UserProfile
    private let repository: AppRepository
    private let storage: AssetStorage
    private let photoLibrary: PhotoLibraryService
    private let nearby: NearbySessionService
    private(set) var selectedContributorID: UUID?

    var isHost: Bool { album.localRole == .host }
    var isActivelyHosting: Bool { nearby.activeHostedAlbumID == album.id }
    var sections: [PhotoSection] {
        let photos = selectedContributorID.map { id in album.photos.filter { $0.contributorID == id } } ?? album.photos
        let calendar = Calendar.current
        let groups = Dictionary(grouping: photos) { photo -> Date? in
            guard let date = photo.capturedAt else { return nil }
            return calendar.startOfDay(for: date)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return groups.keys.sorted {
            switch ($0, $1) {
            case let (lhs?, rhs?): return lhs < rhs
            case (nil, _): return false
            case (_, nil): return true
            }
        }.map { key in
            let title = key.map { formatter.string(from: $0).uppercased() } ?? L10n.text("album.unknownDate")
            return PhotoSection(
                title: title,
                photos: (groups[key] ?? []).sorted { ($0.capturedAt ?? $0.importedAt) < ($1.capturedAt ?? $1.importedAt) }
            )
        }
    }

    init(
        album: Album,
        profile: UserProfile,
        repository: AppRepository,
        storage: AssetStorage,
        photoLibrary: PhotoLibraryService,
        nearby: NearbySessionService
    ) {
        self.profile = profile
        self.repository = repository
        self.storage = storage
        self.photoLibrary = photoLibrary
        self.nearby = nearby
        var storedAlbum = repository.album(id: album.id) ?? album
        if storedAlbum.localRole == .host, nearby.activeHostedAlbumID != storedAlbum.id {
            storedAlbum.connectionState = .offline
            repository.saveAlbum(storedAlbum)
        }
        self.album = storedAlbum
    }

    func start() {
        nearby.delegate = self
    }

    func setContributor(_ id: UUID?) {
        selectedContributorID = id
        onUpdate?()
    }

    func addPhotos(from viewController: UIViewController) {
        onImporting?(true)
        photoLibrary.presentPicker(from: viewController, albumID: album.id, contributor: profile) { [weak self] result in
            guard let self else { return }
            self.onImporting?(false)
            switch result {
            case .success(let photos):
                guard !photos.isEmpty else { return }
                let existing = Set(self.album.photos.compactMap(\.contentHash))
                let unique = photos.filter { item in
                    guard let hash = item.contentHash else { return true }
                    return !existing.contains(hash)
                }
                self.album.photos.append(contentsOf: unique)
                self.album.updatedAt = Date()
                self.repository.saveAlbum(self.album)
                self.nearby.send(album: self.album)
                for photo in unique {
                    if let url = self.storage.absoluteURL(for: photo.photoResourcePath) {
                        self.nearby.sendResource(at: url, photoID: photo.id, kind: .photo, to: nil)
                    }
                    if let url = self.storage.absoluteURL(for: photo.pairedVideoPath) {
                        self.nearby.sendResource(at: url, photoID: photo.id, kind: .pairedVideo, to: nil)
                    }
                    if let url = self.storage.absoluteURL(for: photo.thumbnailPath) {
                        self.nearby.sendResource(at: url, photoID: photo.id, kind: .thumbnail, to: nil)
                    }
                    let task = TransferTask(
                        id: UUID(),
                        albumID: self.album.id,
                        photoID: photo.id,
                        title: L10n.text(photo.isLivePhoto ? "photo.type.live" : "photo.type.still"),
                        direction: .upload,
                        status: .completed,
                        progress: 1,
                        peerName: self.isHost ? "Album" : "Host"
                    )
                    self.repository.saveTransfer(task)
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.onUpdate?()
            case .failure(let error):
                self.onError?(error.localizedDescription)
            }
        }
    }

    func photo(at indexPath: IndexPath) -> PhotoItem {
        sections[indexPath.section].photos[indexPath.item]
    }

    func requestOriginals(at indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            let photo = photo(at: indexPath)
            guard photo.assetState != .originalAvailable else { continue }
            nearby.requestOriginal(photoID: photo.id)
        }
    }

    func nearbyService(_ service: NearbySessionService, didReceive event: NearbyEvent) {
        switch event {
        case .albumReceived(let incoming):
            let existingIDs = Set(album.photos.map(\.id))
            let additions = incoming.photos
                .filter { !existingIDs.contains($0.id) }
                .map { $0.remoteMetadataCopy() }
            album.photos.append(contentsOf: additions)
            let memberIDs = Set(album.members.map(\.id))
            album.members.append(contentsOf: incoming.members.filter { !memberIDs.contains($0.id) })
            album.connectionState = .connected
            album.updatedAt = Date()
            repository.saveAlbum(album)
            if isHost { nearby.send(album: album) }
            onUpdate?()
        case .stateChanged(let state):
            album.connectionState = state
            repository.saveAlbum(album)
            onUpdate?()
        case .peersChanged(let peers):
            if isHost {
                album.members = [album.members.first].compactMap { $0 } + peers
                repository.saveAlbum(album)
                sendExistingThumbnails()
                onUpdate?()
            }
        case .error(let message):
            onError?(message)
        case .resourceReceived(let photoID, let kind, let url):
            guard let index = album.photos.firstIndex(where: { $0.id == photoID }) else { return }
            do {
                switch kind {
                case .thumbnail:
                    album.photos[index].thumbnailPath = try storage.storeResource(
                        from: url,
                        albumID: album.id,
                        photoID: photoID,
                        filename: "thumbnail.jpg"
                    )
                    if isHost, let storedURL = storage.absoluteURL(for: album.photos[index].thumbnailPath) {
                        nearby.sendResource(at: storedURL, photoID: photoID, kind: .thumbnail, to: nil)
                    }
                case .photo:
                    album.photos[index].photoResourcePath = try storage.storeResource(
                        from: url,
                        albumID: album.id,
                        photoID: photoID,
                        filename: "original"
                    )
                    if !album.photos[index].isLivePhoto || album.photos[index].pairedVideoPath != nil {
                        album.photos[index].assetState = .originalAvailable
                    }
                case .pairedVideo:
                    album.photos[index].pairedVideoPath = try storage.storeResource(
                        from: url,
                        albumID: album.id,
                        photoID: photoID,
                        filename: "paired.mov"
                    )
                    if album.photos[index].photoResourcePath != nil {
                        album.photos[index].assetState = .originalAvailable
                    }
                }
                try? FileManager.default.removeItem(at: url)
                repository.saveAlbum(album)
                onUpdate?()
            } catch {
                onError?(error.localizedDescription)
            }
        case .resourceRequested(let photoID, let peerName):
            guard isHost, let photo = album.photos.first(where: { $0.id == photoID }) else { return }
            if let url = storage.absoluteURL(for: photo.photoResourcePath) {
                nearby.sendResource(at: url, photoID: photoID, kind: .photo, to: peerName)
            }
            if let url = storage.absoluteURL(for: photo.pairedVideoPath) {
                nearby.sendResource(at: url, photoID: photoID, kind: .pairedVideo, to: peerName)
            }
        }
    }

    private func sendExistingThumbnails() {
        for photo in album.photos {
            if let thumbnailURL = storage.absoluteURL(for: photo.thumbnailPath) {
                nearby.sendResource(at: thumbnailURL, photoID: photo.id, kind: .thumbnail, to: nil)
            }
        }
    }
}

final class AlbumDetailViewController: BaseViewController {
    var onStartHosting: ((Album) -> Void)?
    var onOpenPhoto: ((PhotoItem, Album) -> Void)?
    var onShowTransfers: (() -> Void)?

    private let viewModel: AlbumDetailViewModel
    private let storage: AssetStorage
    private let collectionView: UICollectionView
    private let emptyView = UIView()
    private let emptyTitle = UILabel()
    private let emptySubtitle = UILabel()
    private let offlineBanner = UILabel()
    private let filterButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .medium)
    private let gridColumnCount: CGFloat = 3

    init(viewModel: AlbumDetailViewModel, storage: AssetStorage) {
        self.viewModel = viewModel
        self.storage = storage
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        layout.sectionInset = UIEdgeInsets(top: 8, left: 2, bottom: 20, right: 2)
        layout.headerReferenceSize = CGSize(width: 0, height: 42)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.album.name
        navigationItem.largeTitleDisplayMode = .never
        configureNavigation()
        configureCollection()
        configureEmptyState()
        configureBottomControls()

        viewModel.onUpdate = { [weak self] in self?.render() }
        viewModel.onError = { [weak self] message in self?.showError(message) }
        viewModel.onImporting = { [weak self] active in
            active ? self?.activity.startAnimating() : self?.activity.stopAnimating()
        }
        viewModel.start()
        render()
    }

    private func configureNavigation() {
        let people = UIBarButtonItem(
            image: UIImage(systemName: "person.2"),
            style: .plain,
            target: nil,
            action: nil
        )
        people.menu = UIMenu(children: viewModel.album.members.map {
            UIAction(title: $0.displayName, subtitle: $0.role.rawValue.capitalized, image: UIImage(systemName: "person.crop.circle")) { _ in }
        })
        let transfers = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up.arrow.down.circle"),
            style: .plain,
            target: self,
            action: #selector(transfersTapped)
        )
        var items = [people, transfers]
        if viewModel.isHost {
            let hosting = UIBarButtonItem(
                image: UIImage(systemName: viewModel.isActivelyHosting ? "qrcode" : "person.badge.plus"),
                style: .plain,
                target: self,
                action: #selector(hostingTapped)
            )
            hosting.accessibilityLabel = L10n.text(
                viewModel.isActivelyHosting ? "album.showInvite" : "album.startHosting"
            )
            items.insert(hosting, at: 0)
        }
        navigationItem.rightBarButtonItems = items
    }

    private func configureCollection() {
        collectionView.backgroundColor = .clear
        collectionView.semanticContentAttribute = .forceLeftToRight
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.contentInset.bottom = 100
        collectionView.register(PhotoGridCell.self, forCellWithReuseIdentifier: PhotoGridCell.reuseID)
        collectionView.register(
            PhotoSectionHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: PhotoSectionHeader.reuseID
        )

        offlineBanner.text = L10n.text("album.offline.message")
        offlineBanner.font = .preferredFont(forTextStyle: .footnote)
        offlineBanner.textColor = .secondaryLabel
        offlineBanner.textAlignment = .center
        offlineBanner.numberOfLines = 0
        offlineBanner.backgroundColor = .secondarySystemBackground

        view.addSubviews(collectionView, offlineBanner)
        offlineBanner.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
            make.height.greaterThanOrEqualTo(36)
        }
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(offlineBanner.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func configureEmptyState() {
        emptyTitle.text = L10n.text("album.noPhotos")
        emptyTitle.font = .preferredFont(forTextStyle: .title2)
        emptyTitle.textAlignment = .center
        emptySubtitle.text = L10n.text(viewModel.isHost ? "album.noPhotos.host" : "album.noPhotos.participant")
        emptySubtitle.font = .preferredFont(forTextStyle: .body)
        emptySubtitle.textColor = .secondaryLabel
        emptySubtitle.textAlignment = .center
        emptySubtitle.numberOfLines = 0
        let icon = UIImageView(image: UIImage(systemName: "photo.on.rectangle"))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        let stack = UIStackView(arrangedSubviews: [icon, emptyTitle, emptySubtitle])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.medium
        emptyView.addSubview(stack)
        view.addSubview(emptyView)
        icon.snp.makeConstraints { $0.width.height.equalTo(56) }
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }
        emptyView.snp.makeConstraints { make in
            make.center.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(AppSpacing.xLarge)
        }
    }

    private func configureBottomControls() {
        var filterConfiguration = UIButton.Configuration.plain()
        filterConfiguration.title = L10n.text("album.everyone")
        filterConfiguration.image = UIImage(systemName: "line.3.horizontal.decrease")
        filterConfiguration.imagePadding = 6
        filterButton.configuration = filterConfiguration
        filterButton.showsMenuAsPrimaryAction = true

        let add = AppDesignSystem.button(
            title: L10n.text("album.addPhotos"),
            image: UIImage(systemName: "plus"),
            style: .primary
        )
        add.addTarget(self, action: #selector(addPhotosTapped), for: .touchUpInside)
        let select = AppDesignSystem.button(title: L10n.text("album.select"), style: .secondary)
        select.addTarget(self, action: #selector(selectTapped), for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [filterButton, add, select, activity])
        row.spacing = AppSpacing.small
        row.alignment = .center
        let floating = FloatingControlContainer()
        floating.contentView.addSubview(row)
        view.addSubview(floating)
        floating.snp.makeConstraints { make in
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(AppSpacing.large)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(AppSpacing.small)
        }
        row.snp.makeConstraints { $0.edges.equalToSuperview().inset(6) }
        updateFilterMenu()
    }

    private func render() {
        title = viewModel.album.name
        configureNavigation()
        offlineBanner.isHidden = viewModel.album.connectionState == .connected || viewModel.album.connectionState == .hosting
        collectionView.reloadData()
        emptyView.isHidden = !viewModel.album.photos.isEmpty
        updateFilterMenu()
    }

    private func updateFilterMenu() {
        let all = UIAction(
            title: L10n.text("album.everyone"),
            state: viewModel.selectedContributorID == nil ? .on : .off
        ) { [weak self] _ in self?.viewModel.setContributor(nil) }
        let members = viewModel.album.members.map { member in
            UIAction(
                title: member.displayName,
                state: viewModel.selectedContributorID == member.id ? .on : .off
            ) { [weak self] _ in self?.viewModel.setContributor(member.id) }
        }
        filterButton.menu = UIMenu(children: [all] + members)
    }

    @objc private func addPhotosTapped() {
        viewModel.addPhotos(from: self)
    }

    @objc private func selectTapped() {
        collectionView.allowsMultipleSelection = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.text("common.cancel"),
            style: .plain,
            target: self,
            action: #selector(cancelSelection)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.text("photo.downloadOriginal"),
            style: .plain,
            target: self,
            action: #selector(downloadSelection)
        )
    }

    @objc private func cancelSelection() {
        collectionView.indexPathsForSelectedItems?.forEach { collectionView.deselectItem(at: $0, animated: true) }
        collectionView.allowsMultipleSelection = false
        navigationItem.leftBarButtonItem = nil
        configureNavigation()
        title = viewModel.album.name
    }

    @objc private func downloadSelection() {
        viewModel.requestOriginals(at: collectionView.indexPathsForSelectedItems ?? [])
        cancelSelection()
    }

    @objc private func transfersTapped() { onShowTransfers?() }

    @objc private func hostingTapped() {
        onStartHosting?(viewModel.album)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: L10n.text("error.generic"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.text("common.ok"), style: .default))
        present(alert, animated: true)
    }
}

extension AlbumDetailViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func numberOfSections(in collectionView: UICollectionView) -> Int { viewModel.sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        viewModel.sections[section].photos.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoGridCell.reuseID, for: indexPath) as! PhotoGridCell
        let photo = viewModel.photo(at: indexPath)
        cell.configure(photo: photo, image: storage.image(at: photo.thumbnailPath))
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: PhotoSectionHeader.reuseID,
            for: indexPath
        ) as! PhotoSectionHeader
        header.configure(title: viewModel.sections[indexPath.section].title)
        return header
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        guard let layout = collectionViewLayout as? UICollectionViewFlowLayout else {
            let width = floor(collectionView.bounds.width / gridColumnCount)
            return CGSize(width: width, height: width)
        }
        let horizontalInsets = layout.sectionInset.left + layout.sectionInset.right
        let horizontalSpacing = layout.minimumInteritemSpacing * (gridColumnCount - 1)
        let availableWidth = collectionView.bounds.width - horizontalInsets - horizontalSpacing
        let width = floor(availableWidth / gridColumnCount)
        return CGSize(width: width, height: width)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView.allowsMultipleSelection {
            title = L10n.text("album.selection.count", collectionView.indexPathsForSelectedItems?.count ?? 0)
        } else {
            onOpenPhoto?(viewModel.photo(at: indexPath), viewModel.album)
        }
    }
}

private final class PhotoGridCell: UICollectionViewCell {
    static let reuseID = "PhotoGridCell"
    private let imageView = UIImageView()
    private let liveBadge = UIImageView(image: UIImage(systemName: "livephoto"))
    private let cloudBadge = UIImageView(image: UIImage(systemName: "icloud.and.arrow.down"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        liveBadge.tintColor = .white
        cloudBadge.tintColor = .white
        [liveBadge, cloudBadge].forEach {
            $0.backgroundColor = UIColor.black.withAlphaComponent(0.4)
            $0.layer.cornerRadius = 10
        }
        contentView.addSubviews(imageView, liveBadge, cloudBadge)
        imageView.snp.makeConstraints { $0.edges.equalToSuperview() }
        liveBadge.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(6)
            make.width.height.equalTo(20)
        }
        cloudBadge.snp.makeConstraints { make in
            make.bottom.trailing.equalToSuperview().inset(6)
            make.width.height.equalTo(20)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isSelected: Bool {
        didSet {
            contentView.layer.borderWidth = isSelected ? 3 : 0
            contentView.layer.borderColor = UIColor.systemBlue.cgColor
        }
    }

    func configure(photo: PhotoItem, image: UIImage?) {
        imageView.image = image ?? UIImage(systemName: "photo")
        imageView.tintColor = .tertiaryLabel
        liveBadge.isHidden = !photo.isLivePhoto
        cloudBadge.isHidden = photo.assetState == .originalAvailable
    }
}

private final class PhotoSectionHeader: UICollectionReusableView {
    static let reuseID = "PhotoSectionHeader"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .preferredFont(forTextStyle: .headline)
        addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(AppSpacing.large)
            make.centerY.equalToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    func configure(title: String) { label.text = title }
}
