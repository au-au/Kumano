import UIKit
import SnapKit

enum AppSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
    static let xxLarge: CGFloat = 32
}

enum AppButtonStyle {
    case primary
    case secondary
    case destructive
}

enum AppDesignSystem {
    static func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        if #available(iOS 26.0, *) {
            appearance.configureWithTransparentBackground()
        } else {
            appearance.configureWithDefaultBackground()
        }
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    static func button(title: String, image: UIImage? = nil, style: AppButtonStyle) -> UIButton {
        let button = UIButton(type: .system)
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            switch style {
            case .primary:
                configuration = .prominentGlass()
            case .secondary:
                configuration = .glass()
            case .destructive:
                configuration = .prominentGlass()
                configuration.baseBackgroundColor = .systemRed
            }
        } else {
            switch style {
            case .primary:
                configuration = .filled()
            case .secondary:
                configuration = .tinted()
            case .destructive:
                configuration = .filled()
                configuration.baseBackgroundColor = .systemRed
            }
        }
        configuration.title = title
        configuration.image = image
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .large
        button.configuration = configuration
        button.snp.makeConstraints { $0.height.greaterThanOrEqualTo(50) }
        return button
    }
}

final class FloatingControlContainer: UIVisualEffectView {
    init() {
        if #available(iOS 26.0, *) {
            super.init(effect: UIGlassEffect(style: .regular))
        } else {
            super.init(effect: UIBlurEffect(style: .systemMaterial))
        }
        clipsToBounds = true
        layer.cornerCurve = .continuous
        layer.cornerRadius = 28
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class BaseViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.backButtonDisplayMode = .minimal
    }
}

extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach(addSubview)
    }
}

extension UIImage {
    static func initials(_ text: String, size: CGSize = CGSize(width: 80, height: 80)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.secondarySystemFill.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.width * 0.32, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let bounds = attributed.boundingRect(
                with: size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            attributed.draw(at: CGPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2))
        }
    }
}
