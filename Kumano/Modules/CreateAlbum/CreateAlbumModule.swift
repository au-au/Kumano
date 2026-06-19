import UIKit
import SnapKit

final class CreateAlbumViewModel {
    private let repository: AppRepository
    private let profile: UserProfile

    init(repository: AppRepository, profile: UserProfile) {
        self.repository = repository
        self.profile = profile
    }

    func create(name: String, startDate: Date?, endDate: Date?) -> Album? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 60 else { return nil }
        let host = Member(
            id: profile.memberID,
            displayName: profile.displayName,
            role: .host,
            connectionState: .hosting
        )
        let album = Album(
            id: UUID(),
            name: trimmed,
            startDate: startDate,
            endDate: endDate,
            createdAt: Date(),
            updatedAt: Date(),
            localRole: .host,
            hostMemberID: profile.memberID,
            connectionState: .hosting,
            members: [host],
            photos: []
        )
        repository.saveAlbum(album)
        return album
    }
}

final class CreateAlbumViewController: BaseViewController {
    var onCreated: ((Album) -> Void)?
    private let viewModel: CreateAlbumViewModel
    private let nameField = UITextField()
    private let datesSwitch = UISwitch()
    private let startPicker = UIDatePicker()
    private let endPicker = UIDatePicker()
    private lazy var createButton = AppDesignSystem.button(title: L10n.text("albums.create"), style: .primary)

    init(viewModel: CreateAlbumViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("albums.create")
        navigationItem.largeTitleDisplayMode = .never

        nameField.placeholder = L10n.text("album.name")
        nameField.borderStyle = .roundedRect
        nameField.returnKeyType = .done
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)

        let dateLabel = UILabel()
        dateLabel.text = L10n.text("album.tripDates")
        dateLabel.font = .preferredFont(forTextStyle: .body)
        let dateHeader = UIStackView(arrangedSubviews: [dateLabel, datesSwitch])
        dateHeader.distribution = .equalSpacing
        startPicker.datePickerMode = .date
        endPicker.datePickerMode = .date
        startPicker.preferredDatePickerStyle = .compact
        endPicker.preferredDatePickerStyle = .compact
        datesSwitch.addTarget(self, action: #selector(datesChanged), for: .valueChanged)

        let dates = UIStackView(arrangedSubviews: [startPicker, endPicker])
        dates.axis = .horizontal
        dates.distribution = .equalSpacing
        dates.isHidden = true
        dates.tag = 42

        let stack = UIStackView(arrangedSubviews: [nameField, dateHeader, dates, createButton])
        stack.axis = .vertical
        stack.spacing = AppSpacing.large
        stack.setCustomSpacing(AppSpacing.xxLarge, after: nameField)
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(AppSpacing.xLarge)
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(AppSpacing.large)
        }
        nameField.snp.makeConstraints { $0.height.equalTo(52) }
        createButton.isEnabled = false
        createButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)
    }

    @objc private func nameChanged() {
        let count = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
        createButton.isEnabled = (1...60).contains(count)
    }

    @objc private func datesChanged() {
        view.viewWithTag(42)?.isHidden = !datesSwitch.isOn
    }

    @objc private func createTapped() {
        guard let album = viewModel.create(
            name: nameField.text ?? "",
            startDate: datesSwitch.isOn ? startPicker.date : nil,
            endDate: datesSwitch.isOn ? endPicker.date : nil
        ) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onCreated?(album)
    }
}
