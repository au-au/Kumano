import UIKit
import SnapKit

final class OnboardingViewModel {
    private let repository: AppRepository

    init(repository: AppRepository) {
        self.repository = repository
    }

    func submit(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...24).contains(trimmed.count) else { return false }
        repository.saveProfile(UserProfile(memberID: UUID(), displayName: trimmed))
        return true
    }
}

final class OnboardingViewController: BaseViewController {
    var onComplete: (() -> Void)?

    private let viewModel: OnboardingViewModel
    private let nameField = UITextField()
    private lazy var continueButton = AppDesignSystem.button(
        title: L10n.text("common.continue"),
        image: UIImage(systemName: "arrow.right"),
        style: .primary
    )

    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true

        let icon = UIImageView(image: UIImage(systemName: "photo.on.rectangle.angled"))
        icon.tintColor = .label
        icon.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.text = L10n.text("onboarding.title")
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        let subtitleLabel = UILabel()
        subtitleLabel.text = L10n.text("onboarding.subtitle")
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        nameField.placeholder = L10n.text("onboarding.name.placeholder")
        nameField.borderStyle = .roundedRect
        nameField.textContentType = .name
        nameField.returnKeyType = .continue
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(textChanged), for: .editingChanged)

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, subtitleLabel, nameField, continueButton])
        stack.axis = .vertical
        stack.spacing = AppSpacing.large
        stack.setCustomSpacing(AppSpacing.xxLarge, after: icon)
        stack.setCustomSpacing(AppSpacing.xLarge, after: subtitleLabel)
        view.addSubview(stack)

        icon.snp.makeConstraints { make in
            make.width.height.equalTo(72)
            make.leading.equalToSuperview()
        }
        nameField.snp.makeConstraints { $0.height.equalTo(52) }
        stack.snp.makeConstraints { make in
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(AppSpacing.xLarge)
            make.centerY.equalTo(view.safeAreaLayoutGuide).offset(-24)
        }

        continueButton.isEnabled = false
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
    }

    @objc private func textChanged() {
        let count = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
        continueButton.isEnabled = (1...24).contains(count)
    }

    @objc private func continueTapped() {
        guard viewModel.submit(name: nameField.text ?? "") else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onComplete?()
    }
}

extension OnboardingViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        continueTapped()
        return true
    }
}
