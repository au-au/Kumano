import UIKit
import AVFoundation
import SnapKit

final class JoinAlbumViewModel: NearbySessionServiceDelegate {
    enum State {
        case idle
        case searching
        case found
        case connecting
        case connected
        case error(String)
    }

    var onUpdate: (() -> Void)?
    private(set) var state: State = .idle
    private let profile: UserProfile
    private let nearby: NearbySessionService

    init(profile: UserProfile, nearby: NearbySessionService) {
        self.profile = profile
        self.nearby = nearby
    }

    func search(code: String) {
        state = .searching
        onUpdate?()
        nearby.delegate = self
        nearby.search(code: code, profile: profile)
    }

    func join() {
        state = .connecting
        onUpdate?()
        nearby.joinFoundAlbum()
    }

    func nearbyService(_ service: NearbySessionService, didReceive event: NearbyEvent) {
        switch event {
        case .stateChanged(let connection):
            switch connection {
            case .searching: state = .searching
            case .connecting:
                if case .searching = state { state = .found }
            case .connected: state = .connected
            case .failed: state = .error(L10n.text("join.notFound"))
            default: break
            }
            onUpdate?()
        case .error(let message):
            state = .error(message)
            onUpdate?()
        case .albumReceived, .peersChanged, .resourceReceived, .resourceRequested:
            break
        }
    }
}

final class JoinAlbumViewController: BaseViewController {
    var onJoin: (() -> Void)?

    private let viewModel: JoinAlbumViewModel
    private let segmented = UISegmentedControl(items: [L10n.text("join.code"), L10n.text("join.scan")])
    private let codeField = UITextField()
    private let statusLabel = UILabel()
    private let scannerView = QRScannerView()
    private lazy var joinButton = AppDesignSystem.button(title: L10n.text("join.action"), style: .primary)

    init(viewModel: JoinAlbumViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("albums.join")
        navigationItem.largeTitleDisplayMode = .never

        segmented.selectedSegmentIndex = 0
        segmented.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        codeField.placeholder = "ABC 123"
        codeField.font = .monospacedSystemFont(ofSize: 34, weight: .semibold)
        codeField.textAlignment = .center
        codeField.autocapitalizationType = .allCharacters
        codeField.autocorrectionType = .no
        codeField.borderStyle = .roundedRect
        codeField.addTarget(self, action: #selector(codeChanged), for: .editingChanged)
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        scannerView.isHidden = true
        scannerView.onCode = { [weak self] code in
            self?.segmented.selectedSegmentIndex = 0
            self?.modeChanged()
            self?.codeField.text = code
            self?.beginSearch(code)
        }
        joinButton.isHidden = true
        joinButton.addTarget(self, action: #selector(joinTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [segmented, codeField, scannerView, statusLabel, joinButton])
        stack.axis = .vertical
        stack.spacing = AppSpacing.xLarge
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(AppSpacing.xLarge)
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(AppSpacing.large)
        }
        codeField.snp.makeConstraints { $0.height.equalTo(64) }
        scannerView.snp.makeConstraints { $0.height.equalTo(360) }
        viewModel.onUpdate = { [weak self] in self?.render() }
    }

    @objc private func modeChanged() {
        let scanning = segmented.selectedSegmentIndex == 1
        codeField.isHidden = scanning
        scannerView.isHidden = !scanning
        statusLabel.text = nil
        joinButton.isHidden = true
        scanning ? scannerView.start() : scannerView.stop()
    }

    @objc private func codeChanged() {
        let normalized = String((codeField.text ?? "").uppercased().filter { $0.isLetter || $0.isNumber })
        if normalized.count <= 6 {
            if normalized.count > 3 {
                let index = normalized.index(normalized.startIndex, offsetBy: 3)
                codeField.text = "\(normalized[..<index]) \(normalized[index...])"
            } else {
                codeField.text = normalized
            }
        }
        if normalized.count == 6 { beginSearch(normalized) }
    }

    private func beginSearch(_ code: String) {
        view.endEditing(true)
        viewModel.search(code: code)
    }

    private func render() {
        switch viewModel.state {
        case .idle:
            statusLabel.text = nil
            joinButton.isHidden = true
        case .searching:
            statusLabel.text = L10n.text("join.searching")
            joinButton.isHidden = true
        case .found:
            statusLabel.text = L10n.text("join.found")
            joinButton.isHidden = false
        case .connecting:
            statusLabel.text = L10n.text("sync.connecting")
            joinButton.isHidden = true
        case .connected:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onJoin?()
        case .error(let message):
            statusLabel.text = message
            joinButton.isHidden = true
        }
    }

    @objc private func joinTapped() {
        viewModel.join()
    }
}

private final class QRScannerView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.cornerRadius = 20
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        preview?.frame = bounds
    }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.configureAndStart() }
        }
    }

    func stop() {
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.stopRunning() }
        }
    }

    private func configureAndStart() {
        if session.inputs.isEmpty {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            layer.insertSublayer(preview, at: 0)
            self.preview = preview
            setNeedsLayout()
        }
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,
              let data = Data(base64Encoded: value),
              let payload = try? JSONDecoder().decode(JoinPayload.self, from: data) else { return }
        stop()
        onCode?(payload.code)
    }
}
