import UIKit

struct AppEnvironment {
    let repository: AppRepository
    let assetStorage: AssetStorage
    let photoLibrary: PhotoLibraryService
    let nearby: NearbySessionService

    static var live: AppEnvironment {
        let storage = LocalAssetStorage()
        return AppEnvironment(
            repository: FileAppRepository(),
            assetStorage: storage,
            photoLibrary: SystemPhotoLibraryService(storage: storage),
            nearby: MultipeerNearbySessionService()
        )
    }
}

final class AppCoordinator {
    private let window: UIWindow
    private let environment: AppEnvironment
    private let navigationController = UINavigationController()

    init(window: UIWindow, environment: AppEnvironment) {
        self.window = window
        self.environment = environment
    }

    func start() {
        AppDesignSystem.configureNavigationBar()
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        if environment.repository.profile == nil {
            showOnboarding()
        } else {
            showAlbums(animated: false)
        }
    }

    private func showOnboarding() {
        let viewModel = OnboardingViewModel(repository: environment.repository)
        let controller = OnboardingViewController(viewModel: viewModel)
        controller.onComplete = { [weak self] in self?.showAlbums(animated: true) }
        navigationController.setViewControllers([controller], animated: false)
    }

    private func showAlbums(animated: Bool) {
        let viewModel = AlbumListViewModel(repository: environment.repository)
        let controller = AlbumListViewController(viewModel: viewModel, storage: environment.assetStorage)
        controller.onCreate = { [weak self] in self?.showCreateAlbum() }
        controller.onJoin = { [weak self] in self?.showJoinAlbum() }
        controller.onOpen = { [weak self] album in self?.showAlbumDetail(album) }
        navigationController.setViewControllers([controller], animated: animated)
    }

    private func showCreateAlbum() {
        guard let profile = environment.repository.profile else { return }
        let viewModel = CreateAlbumViewModel(repository: environment.repository, profile: profile)
        let controller = CreateAlbumViewController(viewModel: viewModel)
        controller.onCreated = { [weak self] album in self?.showHostLobby(album) }
        navigationController.pushViewController(controller, animated: true)
    }

    private func showHostLobby(_ album: Album) {
        guard let profile = environment.repository.profile else { return }
        let viewModel = HostLobbyViewModel(
            album: album,
            profile: profile,
            repository: environment.repository,
            storage: environment.assetStorage,
            nearby: environment.nearby
        )
        let controller = HostLobbyViewController(viewModel: viewModel)
        controller.onOpenAlbum = { [weak self] album in self?.showAlbumDetail(album) }
        navigationController.pushViewController(controller, animated: true)
    }

    private func showJoinAlbum() {
        guard let profile = environment.repository.profile else { return }
        let viewModel = JoinAlbumViewModel(profile: profile, nearby: environment.nearby)
        let controller = JoinAlbumViewController(viewModel: viewModel)
        controller.onJoin = { [weak self] in self?.showInitialSync() }
        navigationController.pushViewController(controller, animated: true)
    }

    private func showInitialSync() {
        let viewModel = InitialSyncViewModel(nearby: environment.nearby, repository: environment.repository)
        let controller = InitialSyncViewController(viewModel: viewModel)
        controller.onComplete = { [weak self] album in
            self?.navigationController.popToRootViewController(animated: false)
            self?.showAlbumDetail(album)
        }
        navigationController.pushViewController(controller, animated: true)
    }

    private func showAlbumDetail(_ album: Album) {
        guard let profile = environment.repository.profile else { return }
        let viewModel = AlbumDetailViewModel(
            album: album,
            profile: profile,
            repository: environment.repository,
            storage: environment.assetStorage,
            photoLibrary: environment.photoLibrary,
            nearby: environment.nearby
        )
        let controller = AlbumDetailViewController(viewModel: viewModel, storage: environment.assetStorage)
        controller.onStartHosting = { [weak self] album in self?.showHostLobby(album) }
        controller.onOpenPhoto = { [weak self] photo, album in self?.showPhoto(photo, album: album) }
        controller.onShowTransfers = { [weak self] in self?.showTransfers() }
        navigationController.pushViewController(controller, animated: true)
    }

    private func showPhoto(_ photo: PhotoItem, album: Album) {
        let viewModel = PhotoViewerViewModel(
            photo: photo,
            album: album,
            storage: environment.assetStorage,
            photoLibrary: environment.photoLibrary,
            nearby: environment.nearby
        )
        navigationController.pushViewController(
            PhotoViewerViewController(viewModel: viewModel, storage: environment.assetStorage),
            animated: true
        )
    }

    private func showTransfers() {
        let viewModel = TransferCenterViewModel(repository: environment.repository)
        navigationController.pushViewController(TransferCenterViewController(viewModel: viewModel), animated: true)
    }
}
