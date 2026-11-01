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

        tableView.backgroundColor = .clear
        tableView.separatorColor = Theme.hairline
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let topRow = UIStackView(arrangedSubviews: [scanButton, statusPill])
        topRow.axis = .horizontal
        topRow.spacing = 16
        topRow.alignment = .center
        topRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topRow)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            topRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            topRow.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            tableView.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
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
    }

    @objc private func scanTapped() {
        bluetoothManager.scan()
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
