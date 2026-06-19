import UIKit

final class TransferCenterViewModel {
    private let repository: AppRepository
    private(set) var sections: [(String, [TransferTask])] = []

    init(repository: AppRepository) {
        self.repository = repository
        reload()
    }

    func reload() {
        let tasks = repository.transfers
        sections = [
            (L10n.text("transfer.uploading"), tasks.filter { $0.status == .active && $0.direction == .upload }),
            (L10n.text("transfer.downloading"), tasks.filter { $0.status == .active && $0.direction == .download }),
            (L10n.text("transfer.waiting"), tasks.filter { $0.status == .waiting }),
            (L10n.text("transfer.failed"), tasks.filter { $0.status == .failed }),
            (L10n.text("transfer.completed"), tasks.filter { $0.status == .completed })
        ].filter { !$0.1.isEmpty }
    }
}

final class TransferCenterViewController: UITableViewController {
    private let viewModel: TransferCenterViewModel

    init(viewModel: TransferCenterViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("transfer.title")
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Transfer")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { viewModel.sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.sections[section].1.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        viewModel.sections[section].0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let task = viewModel.sections[indexPath.section].1[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "Transfer", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = task.title
        content.secondaryText = "\(task.peerName) · \(Int(task.progress * 100))%"
        content.image = UIImage(systemName: task.direction == .upload ? "arrow.up.circle" : "arrow.down.circle")
        cell.contentConfiguration = content
        return cell
    }
}
