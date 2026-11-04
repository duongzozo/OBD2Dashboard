import UIKit

/// Every PID the app knows: current value, data source, session min/max and a
/// short trend line, plus CSV recording. PIDs the ECU does not support sink to
/// the bottom and say so rather than sitting at "--" unexplained.
final class LiveDataViewController: UIViewController {
    private let viewModel = LiveDataViewModel.shared
    private let hub = TelemetryHub.shared

    private let statusLabel = UILabel()
    private let recordButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var rows: [LiveDataRow] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Live Data"
        buildLayout()
        bind()
        viewModel.start()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    private func configure(_ button: UIButton, title: String, color: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(Theme.background, for: .normal)
        button.backgroundColor = color
        button.layer.cornerRadius = 8
        button.titleLabel?.font = Theme.labelFont(size: 13, weight: .bold)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    }

    private func buildLayout() {
        statusLabel.font = Theme.labelFont(size: 13)
        statusLabel.textColor = Theme.textSecondary
        statusLabel.numberOfLines = 2
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configure(recordButton, title: "Start Recording", color: Theme.accent)
        recordButton.addTarget(self, action: #selector(recordTapped), for: .touchUpInside)
        configure(shareButton, title: "Export CSV", color: Theme.accentSecondary)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        configure(resetButton, title: "Reset Min/Max", color: Theme.surfaceElevated)
        resetButton.setTitleColor(Theme.textPrimary, for: .normal)
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)

        let topRow = UIStackView(arrangedSubviews: [statusLabel, resetButton, recordButton, shareButton])
        topRow.axis = .horizontal
        topRow.spacing = 10
        topRow.alignment = .center
        topRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topRow)

        tableView.backgroundColor = .clear
        tableView.separatorColor = Theme.hairline
        tableView.rowHeight = 52
        tableView.allowsSelection = false
        tableView.dataSource = self
        tableView.register(LiveDataCell.self, forCellReuseIdentifier: LiveDataCell.reuseID)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            topRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            topRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            tableView.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func bind() {
        viewModel.rows.observe { [weak self] rows in
            guard let self = self else { return }
            self.rows = rows
            self.updateStatus()
            // Off-screen tabs have nothing to redraw.
            if self.view.window != nil {
                self.tableView.reloadData()
            }
        }
        viewModel.isRecording.observe { [weak self] recording in
            guard let self = self else { return }
            self.configure(self.recordButton, title: recording ? "Stop Recording" : "Start Recording",
                           color: recording ? Theme.danger : Theme.accent)
            self.updateShareButton()
        }
    }

    private func updateShareButton() {
        let canShare = !viewModel.isRecording.value && viewModel.lastLogFile != nil
        shareButton.isEnabled = canShare
        shareButton.alpha = canShare ? 1 : 0.4
    }

    private func updateStatus() {
        if viewModel.isRecording.value {
            statusLabel.text = "Recording: \(viewModel.recordedSampleCount) sample(s), one per second."
            return
        }
        switch hub.ecuState.value {
        case .ecuReady:
            statusLabel.text = "\(hub.supportedPIDs.value.count) PID(s) supported by this ECU. Log files stay in the app's folder in Files."
        case .initializing:
            statusLabel.text = "Connecting to the ECU..."
        case .error(let message):
            statusLabel.text = message
        default:
            statusLabel.text = "No data. Connect the adapter in the Vehicle Info tab, ignition on."
        }
    }

    @objc private func recordTapped() {
        if let message = viewModel.toggleRecording() {
            statusLabel.text = message
        }
        updateShareButton()
    }

    @objc private func shareTapped() {
        guard let file = viewModel.lastLogFile else { return }
        let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = shareButton
        share.popoverPresentationController?.sourceRect = shareButton.bounds
        present(share, animated: true)
    }

    @objc private func resetTapped() {
        viewModel.resetStatistics()
    }
}

extension LiveDataViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: LiveDataCell.reuseID, for: indexPath)
        (cell as? LiveDataCell)?.configure(with: rows[indexPath.row], settings: SettingsStore.shared.settings.value)
        return cell
    }
}

private final class LiveDataCell: UITableViewCell {
    static let reuseID = "liveData"

    private let nameLabel = UILabel()
    private let sourceLabel = UILabel()
    private let trendView = SparklineView()
    private let rangeLabel = UILabel()
    private let valueLabel = UILabel()
    private let unitLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear

        nameLabel.font = Theme.labelFont(size: 15, weight: .semibold)
        sourceLabel.font = Theme.labelFont(size: 10, weight: .bold)
        sourceLabel.textColor = Theme.textTertiary
        rangeLabel.font = Theme.digitFont(size: 12, weight: .regular)
        rangeLabel.textColor = Theme.textSecondary
        rangeLabel.textAlignment = .right
        valueLabel.font = Theme.digitFont(size: 22)
        valueLabel.textAlignment = .right
        unitLabel.font = Theme.labelFont(size: 12)
        unitLabel.textColor = Theme.textSecondary

        let nameStack = UIStackView(arrangedSubviews: [nameLabel, sourceLabel])
        nameStack.axis = .vertical
        nameStack.spacing = 2

        let row = UIStackView(arrangedSubviews: [nameStack, trendView, rangeLabel, valueLabel, unitLabel])
        row.axis = .horizontal
        row.spacing = 14
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameStack.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.30),
            trendView.heightAnchor.constraint(equalToConstant: 34),
            rangeLabel.widthAnchor.constraint(equalToConstant: 150),
            valueLabel.widthAnchor.constraint(equalToConstant: 100),
            unitLabel.widthAnchor.constraint(equalToConstant: 50)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func configure(with row: LiveDataRow, settings: AppSettings) {
        let pid = row.pid
        nameLabel.text = pid.displayName
        nameLabel.textColor = row.isSupported ? Theme.textPrimary : Theme.textTertiary
        unitLabel.text = PIDDisplay.unit(for: pid, settings: settings)
        trendView.values = row.history

        if !row.isSupported {
            sourceLabel.text = "NOT SUPPORTED BY THIS ECU"
            valueLabel.text = "--"
            valueLabel.textColor = Theme.textTertiary
            rangeLabel.text = nil
            return
        }

        sourceLabel.text = "PID \(pid.hexString)" + (row.value.map { " · \($0.source.displayLabel)" } ?? "")
        valueLabel.textColor = Theme.textPrimary
        valueLabel.text = row.value.map { PIDDisplay.format($0.value, pid: pid, settings: settings) } ?? "--"
        if let minimum = row.minimum, let maximum = row.maximum {
            rangeLabel.text = "\(PIDDisplay.format(minimum, pid: pid, settings: settings)) – \(PIDDisplay.format(maximum, pid: pid, settings: settings))"
        } else {
            rangeLabel.text = nil
        }
    }
}

/// Minimal trend line. Scales to its own min/max: it shows direction, and the
/// numeric range beside it gives the scale.
private final class SparklineView: UIView {
    private let lineLayer = CAShapeLayer()

    var values: [Double] = [] {
        didSet { updatePath() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        lineLayer.fillColor = UIColor.clear.cgColor
        lineLayer.strokeColor = Theme.accent.cgColor
        lineLayer.lineWidth = 1.5
        layer.addSublayer(lineLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        lineLayer.frame = bounds
        updatePath()
    }

    private func updatePath() {
        guard values.count > 1, let low = values.min(), let high = values.max(), bounds.width > 0 else {
            lineLayer.path = nil
            return
        }
        let range = high - low
        let stepX = bounds.width / CGFloat(LiveDataViewModel.historyLength - 1)
        let startX = bounds.width - stepX * CGFloat(values.count - 1)
        let path = UIBezierPath()
        for (index, value) in values.enumerated() {
            // A flat signal draws through the middle.
            let fraction = range > 0 ? CGFloat((value - low) / range) : 0.5
            let point = CGPoint(x: startX + stepX * CGFloat(index),
                                y: bounds.height - 2 - fraction * (bounds.height - 4))
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.path = path.cgPath
        CATransaction.commit()
    }
}
