import UIKit

/// Real Phase 5 diagnostic screen: scan stored/pending/permanent DTCs,
/// show description/group/status, and clear with the mandatory
/// confirm-before-clear + re-read-to-verify flow (spec §7). Never clears
/// automatically, and never claims a fault is "fixed" just because its
/// code disappeared after clearing.
final class DiagnosticViewController: UIViewController {
    private lazy var engine = DiagnosticEngine(bluetoothManager: .shared)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var entries: [DTCEntry] = []

    private let scanStoredButton = UIButton(type: .system)
    private let scanPendingButton = UIButton(type: .system)
    private let scanPermanentButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Diagnostic"
        buildLayout()
    }

    private func makeButton(_ title: String, color: UIColor = Theme.accent) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(Theme.background, for: .normal)
        button.backgroundColor = color
        button.layer.cornerRadius = 8
        button.titleLabel?.font = Theme.labelFont(size: 13, weight: .bold)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        return button
    }

    private func buildLayout() {
        statusLabel.font = Theme.labelFont(size: 13)
        statusLabel.textColor = Theme.textSecondary
        statusLabel.text = "No scan performed yet."

        let stored = makeButton("Scan Stored (03)")
        let pending = makeButton("Scan Pending (07)")
        let permanent = makeButton("Scan Permanent (0A)")
        let clear = makeButton("Clear DTCs (04)", color: Theme.danger)
        stored.addTarget(self, action: #selector(scanStoredTapped), for: .touchUpInside)
        pending.addTarget(self, action: #selector(scanPendingTapped), for: .touchUpInside)
        permanent.addTarget(self, action: #selector(scanPermanentTapped), for: .touchUpInside)
        clear.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

        let buttonsRow = UIStackView(arrangedSubviews: [stored, pending, permanent, clear])
        buttonsRow.axis = .horizontal
        buttonsRow.spacing = 10
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false

        tableView.backgroundColor = .clear
        tableView.separatorColor = Theme.hairline
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(buttonsRow)
        view.addSubview(statusLabel)
        view.addSubview(tableView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            buttonsRow.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            buttonsRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),

            statusLabel.topAnchor.constraint(equalTo: buttonsRow.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),

            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func runScan(_ scan: @escaping (@escaping ([DTCEntry]) -> Void) -> Void, label: String) {
        statusLabel.text = "Scanning (\(label))..."
        scan { [weak self] results in
            guard let self = self else { return }
            self.entries = results
            self.statusLabel.text = results.isEmpty ? "\(label): no codes found." : "\(label): \(results.count) code(s) found."
            self.tableView.reloadData()
        }
    }

    @objc private func scanStoredTapped() { runScan(engine.scanStored, label: "Stored") }
    @objc private func scanPendingTapped() { runScan(engine.scanPending, label: "Pending") }
    @objc private func scanPermanentTapped() { runScan(engine.scanPermanent, label: "Permanent") }

    @objc private func clearTapped() {
        let alert = UIAlertController(
            title: "Clear Diagnostic Trouble Codes?",
            message: "Only clear codes while the vehicle is parked safely. Clearing a code does NOT mean the underlying fault is fixed — it only resets the stored record. The code may return if the fault is still present.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear Codes", style: .destructive) { [weak self] _ in
            self?.performClear()
        })
        present(alert, animated: true)
    }

    private func performClear() {
        statusLabel.text = "Clearing..."
        engine.clearDTCs { [weak self] success in
            guard let self = self else { return }
            guard success else {
                self.statusLabel.text = "Clear command failed."
                return
            }
            // Re-read to verify, per spec §7 — never just assume success.
            self.statusLabel.text = "Cleared. Re-reading stored codes to verify..."
            self.engine.scanStored { [weak self] remaining in
                guard let self = self else { return }
                self.entries = remaining
                self.tableView.reloadData()
                self.statusLabel.text = remaining.isEmpty
                    ? "Stored codes cleared and verified empty. This does not guarantee the fault is fixed."
                    : "\(remaining.count) stored code(s) still present after clear."
            }
        }
    }
}

extension DiagnosticViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "dtc") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "dtc")
        let entry = entries[indexPath.row]
        let info = DTCLibrary.info(for: entry.code)
        cell.backgroundColor = .clear
        cell.textLabel?.textColor = Theme.textPrimary
        cell.textLabel?.text = "\(entry.code) — \(info.description)"
        cell.detailTextLabel?.textColor = Theme.textSecondary
        cell.detailTextLabel?.text = "\(info.group)"
        return cell
    }
}
