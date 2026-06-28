import UIKit
import SnapKit

final class AlbumListViewModel {
    private let repository: AppRepository
    private(set) var albums: [Album] = []

    init(repository: AppRepository) {
        self.repository = repository
    }

    func reload() {
        albums = repository.albums
    }
}

final class AlbumListViewController: BaseViewController {
    var onCreate: (() -> Void)?
    var onJoin: (() -> Void)?
    var onOpen: ((Album) -> Void)?
    var onShowInvite: ((Album) -> Void)?
    var onShowSettings: (() -> Void)?

    private let viewModel: AlbumListViewModel
    private let storage: AssetStorage
    private let nearby: NearbySessionService
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyView = EmptyAlbumsView()

    init(viewModel: AlbumListViewModel, storage: AssetStorage, nearby: NearbySessionService) {
        self.viewModel = viewModel
        self.storage = storage
        self.nearby = nearby
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("albums.title")
        navigationController?.navigationBar.prefersLargeTitles = true
        let settingsItem = UIBarButtonItem(
            image: UIImage(systemName: "person.crop.circle"),
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )
        settingsItem.accessibilityLabel = L10n.text("settings.open")
        navigationItem.rightBarButtonItem = settingsItem
        tableView.register(AlbumCell.self, forCellReuseIdentifier: AlbumCell.reuseID)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.contentInset.bottom = 96

        let create = AppDesignSystem.button(
            title: L10n.text("albums.create"),
            image: UIImage(systemName: "plus"),
            style: .primary
        )
        let join = AppDesignSystem.button(
            title: L10n.text("albums.join"),
            image: UIImage(systemName: "qrcode.viewfinder"),
            style: .secondary
        )
        create.addTarget(self, action: #selector(createTapped), for: .touchUpInside)
        join.addTarget(self, action: #selector(joinTapped), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [create, join])
        actions.axis = .horizontal
        actions.spacing = AppSpacing.small
        actions.distribution = .fillEqually
        let floating = FloatingControlContainer()
        floating.contentView.addSubview(actions)

        view.addSubviews(tableView, emptyView, floating)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        emptyView.snp.makeConstraints { make in
            make.center.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(AppSpacing.xLarge)
        }
        floating.snp.makeConstraints { make in
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(AppSpacing.large)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(AppSpacing.small)
        }
        actions.snp.makeConstraints { $0.edges.equalToSuperview().inset(6) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.reload()
        tableView.reloadData()
        emptyView.isHidden = !viewModel.albums.isEmpty
    }

    @objc private func createTapped() { onCreate?() }
    @objc private func joinTapped() { onJoin?() }
    @objc private func settingsTapped() { onShowSettings?() }
}

extension AlbumListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.albums.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AlbumCell.reuseID, for: indexPath) as! AlbumCell
        let album = viewModel.albums[indexPath.row]
        cell.configure(
            album: album,
            image: storage.image(at: album.coverPath),
            isActivelyHosting: nearby.activeHostedAlbumID == album.id
        )
        cell.onShowInvite = { [weak self] in self?.onShowInvite?(album) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onOpen?(viewModel.albums[indexPath.row])
    }
}

private final class EmptyAlbumsView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        let icon = UIImageView(image: UIImage(systemName: "photo.stack"))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        let title = UILabel()
        title.text = L10n.text("albums.empty.title")
        title.font = .preferredFont(forTextStyle: .title2)
        title.textAlignment = .center
        let subtitle = UILabel()
        subtitle.text = L10n.text("albums.empty.subtitle")
        subtitle.font = .preferredFont(forTextStyle: .body)
        subtitle.textColor = .secondaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.medium
        addSubview(stack)
        icon.snp.makeConstraints { $0.width.height.equalTo(56) }
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

private final class AlbumCell: UITableViewCell {
    static let reuseID = "AlbumCell"
    private let cover = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let stateLabel = UILabel()
    private let inviteButton = UIButton(type: .system)
    var onShowInvite: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 12
        cover.backgroundColor = .secondarySystemFill
        nameLabel.font = .preferredFont(forTextStyle: .headline)
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        stateLabel.font = .preferredFont(forTextStyle: .caption1)
        stateLabel.textColor = .secondaryLabel
        inviteButton.addTarget(self, action: #selector(inviteTapped), for: .touchUpInside)
        let labels = UIStackView(arrangedSubviews: [nameLabel, detailLabel, stateLabel])
        labels.axis = .vertical
        labels.spacing = 3
        contentView.addSubviews(cover, labels)
        cover.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(AppSpacing.large)
            make.top.bottom.equalToSuperview().inset(AppSpacing.medium)
            make.width.height.equalTo(72)
        }
        labels.snp.makeConstraints { make in
            make.leading.equalTo(cover.snp.trailing).offset(AppSpacing.medium)
            make.trailing.equalToSuperview().inset(AppSpacing.large)
            make.centerY.equalTo(cover)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        onShowInvite = nil
    }

    func configure(album: Album, image: UIImage?, isActivelyHosting: Bool) {
        cover.image = image ?? UIImage(systemName: "photo")
        cover.tintColor = .tertiaryLabel
        nameLabel.text = album.name
        detailLabel.text = L10n.text("album.summary", album.photos.count, album.members.count)
        let role = L10n.text(album.localRole == .host ? "role.host" : "role.participant")
        let state: ConnectionState = album.localRole == .host && !isActivelyHosting
            ? .offline
            : album.connectionState
        stateLabel.text = "\(role) · \(state.title)"
        if album.localRole == .host {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: isActivelyHosting ? "qrcode" : "person.badge.plus")
            inviteButton.configuration = configuration
            inviteButton.accessibilityLabel = L10n.text(
                isActivelyHosting ? "album.showInvite" : "album.startHosting"
            )
            accessoryType = .none
            accessoryView = inviteButton
        } else {
            accessoryView = nil
            accessoryType = .disclosureIndicator
        }
    }

    @objc private func inviteTapped() {
        onShowInvite?()
    }
}
