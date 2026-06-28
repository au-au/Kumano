import UIKit
import SnapKit

final class SettingsViewModel {
    private let repository: AppRepository
    private let profile: UserProfile

    var displayName: String {
        profile.displayName
    }

    init(repository: AppRepository, profile: UserProfile) {
        self.repository = repository
        self.profile = profile
    }

    func canSave(displayName: String) -> Bool {
        let trimmed = normalized(displayName)
        return (1...24).contains(trimmed.count) && trimmed != profile.displayName
    }

    func save(displayName: String) -> Bool {
        let trimmed = normalized(displayName)
        guard (1...24).contains(trimmed.count) else { return false }
        repository.saveProfile(UserProfile(memberID: profile.memberID, displayName: trimmed))
        return true
    }

    private func normalized(_ displayName: String) -> String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class SettingsViewController: BaseViewController {
    var onSaved: (() -> Void)?

    private let viewModel: SettingsViewModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let nameCell = NicknameCell()
    private lazy var doneButton = UIBarButtonItem(
        title: L10n.text("common.done"),
        style: .done,
        target: self,
        action: #selector(doneTapped)
    )

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("settings.title")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = doneButton

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .interactive

        nameCell.configure(displayName: viewModel.displayName)
        nameCell.onTextChanged = { [weak self] displayName in
            self?.updateDoneButton(displayName: displayName)
        }
        nameCell.onReturn = { [weak self] in
            guard self?.doneButton.isEnabled == true else { return }
            self?.doneTapped()
        }

        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        updateDoneButton(displayName: viewModel.displayName)
    }

    @objc private func doneTapped() {
        guard viewModel.save(displayName: nameCell.displayName) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSaved?()
    }

    private func updateDoneButton(displayName: String) {
        doneButton.isEnabled = viewModel.canSave(displayName: displayName)
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        L10n.text("settings.personalInformation")
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        L10n.text("settings.nickname.footer")
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        nameCell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        nameCell.beginEditing()
    }
}

private final class NicknameCell: UITableViewCell {
    var onTextChanged: ((String) -> Void)?
    var onReturn: (() -> Void)?

    var displayName: String {
        nameField.text ?? ""
    }

    private let titleLabel = UILabel()
    private let nameField = UITextField()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        titleLabel.text = L10n.text("settings.nickname")
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .secondaryLabel
        titleLabel.adjustsFontForContentSizeCategory = true

        nameField.font = .preferredFont(forTextStyle: .body)
        nameField.adjustsFontForContentSizeCategory = true
        nameField.placeholder = L10n.text("settings.nickname.placeholder")
        nameField.textContentType = .nickname
        nameField.autocapitalizationType = .words
        nameField.autocorrectionType = .no
        nameField.clearButtonMode = .whileEditing
        nameField.returnKeyType = .done
        nameField.delegate = self
        nameField.accessibilityLabel = L10n.text("settings.nickname")
        nameField.addTarget(self, action: #selector(textChanged), for: .editingChanged)

        let stack = UIStackView(arrangedSubviews: [titleLabel, nameField])
        stack.axis = .vertical
        stack.spacing = AppSpacing.xSmall
        contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(AppSpacing.large)
        }
        nameField.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(32)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(displayName: String) {
        nameField.text = displayName
    }

    func beginEditing() {
        nameField.becomeFirstResponder()
    }

    @objc private func textChanged() {
        onTextChanged?(displayName)
    }
}

extension NicknameCell: UITextFieldDelegate {
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        guard let current = textField.text,
              let swiftRange = Range(range, in: current) else {
            return false
        }
        return current.replacingCharacters(in: swiftRange, with: string).count <= 24
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onReturn?()
        return true
    }
}
