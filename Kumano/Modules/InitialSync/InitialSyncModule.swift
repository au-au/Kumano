import UIKit
import SnapKit

final class InitialSyncViewModel: NearbySessionServiceDelegate {
    var onProgress: ((Float, String) -> Void)?
    var onComplete: ((Album) -> Void)?
    var onError: ((String) -> Void)?
    private let nearby: NearbySessionService
    private let repository: AppRepository

    init(nearby: NearbySessionService, repository: AppRepository) {
        self.nearby = nearby
        self.repository = repository
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
            repository.saveAlbum(album)
            onProgress?(1, L10n.text("sync.ready"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.onComplete?(album) }
        case .error(let message):
            onError?(message)
        default:
            break
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
