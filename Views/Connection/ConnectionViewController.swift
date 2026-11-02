import UIKit

/// Scan/connect screen for the real ELM327 BLE adapter. This is what the
/// user uses to verify the adapter actually connects — if the configured
/// service/characteristic UUIDs (Settings) don't match the real hardware,
/// `BLETransport` surfaces that as a clear `.error` here instead of
/// silently failing.
final class ConnectionViewController: UIViewController {
    private let bluetoothManager: BluetoothManager
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusPill = StatusPillView()
    private let scanButton = UIButton(type: .system)
    private let copyLogButton = UIButton(type: .system)
    /// On-device BLE log. The build runs sideloaded on an iPad with no
    /// debugger attached, so this panel is the only practical way to read
    /// `CBManagerState` transitions and `didDiscover` traffic while
    /// standing at the car.
    private let logTextView = UITextView()
    private var devices: [DiscoveredPeripheral] = []

    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Connect Adapter"
        view.backgroundColor = Theme.background
        buildLayout()
        bind()
    }

    private func buildLayout() {
        statusPill.translatesAutoresizingMaskIntoConstraints = false

        scanButton.setTitle("Scan for Adapters", for: .normal)
        scanButton.setTitleColor(Theme.background, for: .normal)
        scanButton.backgroundColor = Theme.accent
        scanButton.layer.cornerRadius = 8
        scanButton.titleLabel?.font = Theme.labelFont(size: 15, weight: .bold)
        scanButton.translatesAutoresizingMaskIntoConstraints = false
        scanButton.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)

        copyLogButton.setTitle("Copy Log", for: .normal)
        copyLogButton.setTitleColor(Theme.textSecondary, for: .normal)
        copyLogButton.titleLabel?.font = Theme.labelFont(size: 13, weight: .regular)
        copyLogButton.translatesAutoresizingMaskIntoConstraints = false
        copyLogButton.addTarget(self, action: #selector(copyLogTapped), for: .touchUpInside)

        tableView.backgroundColor = .clear
        tableView.separatorColor = Theme.hairline
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false

        logTextView.isEditable = false
        logTextView.backgroundColor = Theme.surface
        logTextView.textColor = Theme.textSecondary
        logTextView.font = UIFont(name: "Menlo", size: 10) ?? UIFont.systemFont(ofSize: 10)
        logTextView.layer.cornerRadius = 8
        logTextView.translatesAutoresizingMaskIntoConstraints = false

        let topRow = UIStackView(arrangedSubviews: [scanButton, statusPill, copyLogButton])
        topRow.axis = .horizontal
        topRow.spacing = 16
        topRow.alignment = .center
        topRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topRow)
        view.addSubview(tableView)
        view.addSubview(logTextView)

        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            topRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            topRow.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            // Device list on the left, live BLE log on the right — the
            // screen is landscape-locked, so a side-by-side split keeps
            // both readable without scrolling between them.
            tableView.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            tableView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.38),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            logTextView.topAnchor.constraint(equalTo: tableView.topAnchor),
            logTextView.leadingAnchor.constraint(equalTo: tableView.trailingAnchor, constant: 16),
            logTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            logTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    private func bind() {
        bluetoothManager.connectionState.observe { [weak self] state in
            self?.statusPill.update(for: state)
        }
        bluetoothManager.discoveredDevices.observe { [weak self] devices in
            self?.devices = devices
            self?.tableView.reloadData()
        }
        BLELog.shared.entries.observe { [weak self] entries in
            self?.renderLog(entries)
        }
    }

    private func renderLog(_ entries: [String]) {
        logTextView.text = entries.joined(separator: "\n")
        // Keep the newest line visible — during a scan the interesting
        // entry is always the one that just arrived.
        let end = NSRange(location: (logTextView.text as NSString).length, length: 0)
        logTextView.scrollRangeToVisible(end)
    }

    @objc private func scanTapped() {
        bluetoothManager.scan()
    }

    @objc private func copyLogTapped() {
        UIPasteboard.general.string = BLELog.shared.plainText
        copyLogButton.setTitle("Copied", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyLogButton.setTitle("Copy Log", for: .normal)
        }
    }
}

extension ConnectionViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        devices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "device") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "device")
        let device = devices[indexPath.row]
        cell.backgroundColor = .clear
        cell.textLabel?.textColor = Theme.textPrimary
        cell.textLabel?.text = device.name
        cell.detailTextLabel?.textColor = Theme.textSecondary
        if let rssi = device.signalStrength {
            cell.detailTextLabel?.text = "RSSI: \(rssi) dBm"
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        bluetoothManager.connect(to: devices[indexPath.row].id)
    }
}
