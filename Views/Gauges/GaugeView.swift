import UIKit

/// A reusable 270°-sweep analog gauge (speedometer/tachometer style) with a
/// large digital readout in the center. Performance-sensitive by design for
/// iPad mini 3: the track/tick paths are only rebuilt in `layoutSubviews`
/// (on size change), while per-telemetry-tick updates touch only the
/// `valueLayer.strokeEnd` property and label text — never a full
/// `draw(rect:)` redraw of the whole view.
final class GaugeView: UIView {
    var minValue: Double = 0
    var maxValue: Double = 100
    var dangerThreshold: Double?
    var majorTickCount: Int = 6
    var title: String = "" { didSet { titleLabel.text = title.uppercased() } }
    var unit: String = "" { didSet { unitLabel.text = unit } }
    var valueFormatter: (Double) -> String = { String(Int($0.rounded())) }

    private(set) var value: Double = 0

    private let startAngle: CGFloat = 135 * .pi / 180
    private let sweepAngle: CGFloat = 270 * .pi / 180

    private let trackLayer = CAShapeLayer()
    private let valueLayer = CAShapeLayer()
    private let tickLayer = CAShapeLayer()

    private let valueLabel = UILabel()
    private let unitLabel = UILabel()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear

        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = Theme.gaugeTrack.cgColor
        trackLayer.lineCap = .round
        layer.addSublayer(trackLayer)

        tickLayer.fillColor = UIColor.clear.cgColor
        tickLayer.strokeColor = Theme.textTertiary.cgColor
        layer.addSublayer(tickLayer)

        valueLayer.fillColor = UIColor.clear.cgColor
        valueLayer.strokeColor = Theme.accent.cgColor
        valueLayer.lineCap = .round
        valueLayer.strokeEnd = 0
        layer.addSublayer(valueLayer)

        valueLabel.font = Theme.digitFont(size: 40)
        valueLabel.textColor = Theme.textPrimary
        valueLabel.textAlignment = .center
        valueLabel.text = "0"

        unitLabel.font = Theme.labelFont(size: 13)
        unitLabel.textColor = Theme.textSecondary
        unitLabel.textAlignment = .center

        titleLabel.font = Theme.labelFont(size: 12, weight: .semibold)
        titleLabel.textColor = Theme.textTertiary
        titleLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [valueLabel, unitLabel, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 10)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = min(bounds.width, bounds.height) / 2 - 8
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let lineWidth = max(6, radius * 0.07)

        let arcPath = UIBezierPath(arcCenter: center, radius: radius, startAngle: startAngle,
                                    endAngle: startAngle + sweepAngle, clockwise: true)
        trackLayer.path = arcPath.cgPath
        trackLayer.lineWidth = lineWidth
        trackLayer.frame = bounds

        valueLayer.path = arcPath.cgPath
        valueLayer.lineWidth = lineWidth
        valueLayer.frame = bounds

        let ticks = UIBezierPath()
        let tickRadius = radius - lineWidth / 2 - 4
        let tickInner = tickRadius - 10
        for i in 0...majorTickCount {
            let fraction = CGFloat(i) / CGFloat(majorTickCount)
            let angle = startAngle + sweepAngle * fraction
            let outer = CGPoint(x: center.x + tickRadius * cos(angle), y: center.y + tickRadius * sin(angle))
            let inner = CGPoint(x: center.x + tickInner * cos(angle), y: center.y + tickInner * sin(angle))
            ticks.move(to: outer)
            ticks.addLine(to: inner)
        }
        tickLayer.path = ticks.cgPath
        tickLayer.lineWidth = 2
        tickLayer.frame = bounds

        setValue(value, animated: false)
    }

    /// Shows that there is no reading, as opposed to a reading of zero.
    func clearValue() {
        setValue(minValue)
        valueLabel.text = "--"
    }

    /// Updates only the value arc + digital readout — cheap enough to call
    /// on every telemetry tick without triggering a full view redraw.
    func setValue(_ newValue: Double, animated: Bool = false) {
        value = newValue
        let clamped = max(minValue, min(maxValue, newValue))
        let fraction = maxValue > minValue ? CGFloat((clamped - minValue) / (maxValue - minValue)) : 0

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        valueLayer.strokeEnd = fraction
        CATransaction.commit()

        if let danger = dangerThreshold, newValue >= danger {
            valueLayer.strokeColor = Theme.danger.cgColor
        } else {
            valueLayer.strokeColor = Theme.accent.cgColor
        }

        valueLabel.text = valueFormatter(newValue)
    }
}
