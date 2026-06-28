import UIKit
import CoreImage.CIFilterBuiltins
import SnapKit

final class HostLobbyViewModel: NearbySessionServiceDelegate {
    var onUpdate: (() -> Void)?
    var onError: ((String) -> Void)?

    private(set) var album: Album
    private let profile: UserProfile
    private let repository: AppRepository
    private let storage: AssetStorage
    private let nearby: NearbySessionService
    private(set) var connectedMembers: [Member] = []

    var code: String { nearby.joinPayload?.code ?? "----" }
    var qrPayload: String {
        guard let payload = nearby.joinPayload,
              let data = try? JSONEncoder().encode(payload) else { return "" }
        return data.base64EncodedString()
    }

    init(
        album: Album,
        profile: UserProfile,
        repository: AppRepository,
        storage: AssetStorage,
        nearby: NearbySessionService
    ) {
        self.album = album
        self.profile = profile
        self.repository = repository
        self.storage = storage
        self.nearby = nearby
    }

    func start() {
        nearby.delegate = self
        nearby.startHosting(album: album, profile: profile)
        album.connectionState = .hosting
        repository.saveAlbum(album)
        onUpdate?()
    }

    func stop() {
        nearby.stop()
        album.connectionState = .offline
        repository.saveAlbum(album)
        onUpdate?()
    }

    func nearbyService(_ service: NearbySessionService, didReceive event: NearbyEvent) {
        switch event {
        case .stateChanged(let state):
            album.connectionState = state
            repository.saveAlbum(album)
            onUpdate?()
        case .peersChanged(let peers):
            connectedMembers = peers
            album.members = [album.members.first].compactMap { $0 } + peers
            album.updatedAt = Date()
            repository.saveAlbum(album)
            for photo in album.photos {
                if let thumbnailURL = storage.absoluteURL(for: photo.thumbnailPath) {
                    nearby.sendResource(at: thumbnailURL, photoID: photo.id, kind: .thumbnail, to: nil)
                }
            }
            onUpdate?()
        case .albumReceived(let incoming):
            let existingIDs = Set(album.photos.map(\.id))
            let additions = incoming.photos
                .filter { !existingIDs.contains($0.id) }
                .map { $0.remoteMetadataCopy() }
            album.photos.append(contentsOf: additions)
            album.updatedAt = Date()
            repository.saveAlbum(album)
            nearby.send(album: album)
            onUpdate?()
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
                    if let storedURL = storage.absoluteURL(for: album.photos[index].thumbnailPath) {
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
            guard let photo = album.photos.first(where: { $0.id == photoID }) else { return }
            if let url = storage.absoluteURL(for: photo.photoResourcePath) {
                nearby.sendResource(at: url, photoID: photoID, kind: .photo, to: peerName)
            }
            if let url = storage.absoluteURL(for: photo.pairedVideoPath) {
                nearby.sendResource(at: url, photoID: photoID, kind: .pairedVideo, to: peerName)
            }
        case .error(let message):
            onError?(message)
        }
    }
}

final class HostLobbyViewController: BaseViewController {
    var onOpenAlbum: ((Album) -> Void)?
    private let viewModel: HostLobbyViewModel
    private let statusLabel = UILabel()
    private let peopleLabel = UILabel()
    private let codeLabel = UILabel()
    private let qrImageView = UIImageView()
    private let membersStack = UIStackView()

    init(viewModel: HostLobbyViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.album.name
        navigationItem.largeTitleDisplayMode = .never

        statusLabel.text = L10n.text("lobby.waiting")
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.textColor = .secondaryLabel

        peopleLabel.font = .preferredFont(forTextStyle: .subheadline)
        peopleLabel.textAlignment = .center

        codeLabel.font = .monospacedSystemFont(ofSize: 38, weight: .semibold)
        codeLabel.adjustsFontForContentSizeCategory = true
        codeLabel.textAlignment = .center
        codeLabel.accessibilityLabel = "Album code"

        qrImageView.contentMode = .scaleAspectFit
        qrImageView.backgroundColor = .white
        qrImageView.layer.cornerRadius = 16
        qrImageView.clipsToBounds = true

        let help = UILabel()
        help.text = L10n.text("lobby.help")
        help.font = .preferredFont(forTextStyle: .body)
        help.textColor = .secondaryLabel
        help.textAlignment = .center
        help.numberOfLines = 0

        membersStack.axis = .vertical
        membersStack.spacing = AppSpacing.medium

        let open = AppDesignSystem.button(title: L10n.text("lobby.openAlbum"), style: .primary)
        let stop = AppDesignSystem.button(title: L10n.text("lobby.stopHosting"), style: .secondary)
        open.addTarget(self, action: #selector(openTapped), for: .touchUpInside)
        stop.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [open, stop])
        actions.axis = .vertical
        actions.spacing = AppSpacing.small

        let content = UIStackView(arrangedSubviews: [
            statusLabel, peopleLabel, codeLabel, qrImageView, help, membersStack, actions
        ])
        content.axis = .vertical
        content.spacing = AppSpacing.large
        content.setCustomSpacing(AppSpacing.xLarge, after: peopleLabel)
        content.setCustomSpacing(AppSpacing.xLarge, after: help)
        let scroll = UIScrollView()
        scroll.addSubview(content)
        view.addSubview(scroll)
        scroll.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        content.snp.makeConstraints { make in
            make.edges.equalTo(scroll.contentLayoutGuide).inset(AppSpacing.xLarge)
            make.width.equalTo(scroll.frameLayoutGuide).offset(-AppSpacing.xLarge * 2)
        }
        qrImageView.snp.makeConstraints { make in
            make.width.height.equalTo(220)
            make.centerX.equalToSuperview()
        }

        viewModel.onUpdate = { [weak self] in self?.render() }
        viewModel.onError = { [weak self] message in self?.showError(message) }
        viewModel.start()
    }

    private func render() {
        codeLabel.text = formatted(code: viewModel.code)
        peopleLabel.text = L10n.text("lobby.people", viewModel.connectedMembers.count + 1)
        qrImageView.image = qrImage(from: viewModel.qrPayload)
        membersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        membersStack.addArrangedSubview(memberRow(
            name: viewModel.album.members.first?.displayName ?? L10n.text("common.you"),
            detail: L10n.text("lobby.youHost")
        ))
        viewModel.connectedMembers.forEach {
            membersStack.addArrangedSubview(memberRow(name: $0.displayName, detail: $0.connectionState.title))
        }
    }

    private func memberRow(name: String, detail: String) -> UIView {
        let avatar = UIImageView(image: .initials(String(name.prefix(2))))
        avatar.layer.cornerRadius = 20
        avatar.clipsToBounds = true
        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .preferredFont(forTextStyle: .body)
        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .preferredFont(forTextStyle: .caption1)
        detailLabel.textColor = .secondaryLabel
        let labels = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        labels.axis = .vertical
        let row = UIStackView(arrangedSubviews: [avatar, labels])
        row.spacing = AppSpacing.medium
        row.alignment = .center
        avatar.snp.makeConstraints { $0.width.height.equalTo(40) }
        return row
    }

    private func formatted(code: String) -> String {
        String(code.filter { $0.isNumber }.prefix(4))
    }

    private func qrImage(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 9, y: 9)) else { return nil }
        return UIImage(ciImage: output)
    }

    @objc private func openTapped() {
        onOpenAlbum?(viewModel.album)
    }

    @objc private func stopTapped() {
        let alert = UIAlertController(
            title: L10n.text("lobby.stop.title"),
            message: L10n.text("lobby.stop.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.text("lobby.keepHosting"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.text("common.stop"), style: .destructive) { [weak self] _ in
            self?.viewModel.stop()
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: L10n.text("error.generic"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.text("common.ok"), style: .default))
        present(alert, animated: true)
    }
}
