//
//  MapTimelineView.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SnapKit
import UIKit

/// The map's bottom bar for scrubbing back through the past 24 hours.
///
/// Hourly steps only — readings are published on the hour, so a continuous
/// slider would only ever show the same map between ticks. The left end is 24
/// hours before the latest reading and the right end is that reading; there is
/// no forecast, so nothing lies to the right of "now".
final class MapTimelineView: UIView {
    static let preferredHeight: CGFloat = 66

    /// The user moved the scrubber. Hours before the latest reading; 0 is live.
    var onChange: ((Int) -> Void)?
    /// A finger came down on the track, before any change.
    var onInteractionBegan: (() -> Void)?
    var onPlayTapped: (() -> Void)?

    /// Hours before the latest reading the map is showing.
    var hoursAgo = 0 {
        didSet {
            guard hoursAgo != oldValue else { return }
            updateSelection(animated: true)
        }
    }

    /// The latest publish time (`yyyy-MM-ddTHH:mm:ss`). Sets the clock labels;
    /// the bar stays disabled until it arrives.
    var anchor: String? {
        didSet {
            guard anchor != oldValue else { return }
            track.anchor = anchor
            track.isUserInteractionEnabled = anchor != nil
            playButton.isEnabled = anchor != nil
            updateSelection(animated: false)
        }
    }

    var isPlaying = false {
        didSet {
            let symbol = isPlaying ? "pause.fill" : "play.fill"
            playButton.setImage(UIImage(systemName: symbol, withConfiguration: Self.playSymbol), for: .normal)
            playButton.accessibilityLabel = (isPlaying ? "Timeline.pause" : "Timeline.play").localized
        }
    }

    /// Stations loaded out of those in view, while any are outstanding.
    var progress: (done: Int, total: Int)? {
        didSet {
            if let progress, progress.done < progress.total {
                statusLabel.text = String(format: "Timeline.loading".localized, progress.done, progress.total)
                spinner.startAnimating()
            } else {
                statusLabel.text = nil
                spinner.stopAnimating()
            }
        }
    }

    private static let playSymbol = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)

    private let playButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let track = MapTimelineTrack()
    private let selectionFeedback = UISelectionFeedbackGenerator()

    override init(frame: CGRect) {
        super.init(frame: frame)
        createSubviews()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        createSubviews()
    }

    private func createSubviews() {
        translatesAutoresizingMaskIntoConstraints = false

        // Same card treatment as the index pills and the closest-station card.
        backgroundColor = .tertiarySystemBackground
        layer.cornerRadius = 16
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 4
        layer.shadowOpacity = 0.18

        playButton.backgroundColor = IndexSelectorView.accent
        playButton.tintColor = .white
        playButton.layer.cornerRadius = 19
        playButton.isEnabled = false
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        isPlaying = false
        addSubview(playButton)
        playButton.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(38)
        }

        titleLabel.adjustsFontForContentSizeCategory = false
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(playButton.snp.right).offset(12)
            make.top.equalToSuperview().offset(8)
            make.height.equalTo(20)
        }

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabel
        addSubview(statusLabel)
        statusLabel.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-14)
            make.centerY.equalTo(titleLabel)
            make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(8)
        }

        spinner.hidesWhenStopped = true
        spinner.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        addSubview(spinner)
        spinner.snp.makeConstraints { make in
            make.right.equalTo(statusLabel.snp.left).offset(-2)
            make.centerY.equalTo(titleLabel)
        }

        track.isUserInteractionEnabled = false
        track.onScrub = { [weak self] index, phase in self?.scrubbed(to: index, phase: phase) }
        track.onAccessibilityStep = { [weak self] delta in self?.step(by: delta) }
        addSubview(track)
        track.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.right.equalToSuperview().offset(-16)
            make.top.equalTo(titleLabel.snp.bottom).offset(2)
            make.bottom.equalToSuperview().offset(-4)
        }

        updateSelection(animated: false)
    }

    private func scrubbed(to index: Int, phase: MapTimelineTrack.Phase) {
        if phase == .began {
            onInteractionBegan?()
            selectionFeedback.prepare()
        }

        let newHoursAgo = MapHistoryStore.hours - index
        guard newHoursAgo != hoursAgo else { return }
        hoursAgo = newHoursAgo
        selectionFeedback.selectionChanged()
        onChange?(newHoursAgo)
    }

    private func step(by delta: Int) {
        onInteractionBegan?()
        let newHoursAgo = min(max(hoursAgo - delta, 0), MapHistoryStore.hours)
        guard newHoursAgo != hoursAgo else { return }
        hoursAgo = newHoursAgo
        onChange?(newHoursAgo)
    }

    @objc private func playTapped() {
        onPlayTapped?()
    }

    private func updateSelection(animated: Bool) {
        track.setIndex(MapHistoryStore.hours - hoursAgo, animated: animated)
        titleLabel.attributedText = title
        track.accessibilityValue = titleLabel.attributedText?.string
    }

    /// "14:00  3 小時前", "昨天 22:00  19 小時前", or "17:00  最新".
    private var title: NSAttributedString {
        let primary: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor.label,
        ]
        let secondary: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel,
        ]

        guard let anchor, let anchorDate = MapTimeline.date(anchor) else {
            return NSAttributedString(string: "Timeline.title".localized, attributes: secondary)
        }

        let date = anchorDate.addingTimeInterval(-Double(hoursAgo) * 3600)
        var clock = MapTimelineTrack.clockFormatter.string(from: date)
        if !MapTimeline.calendar.isDate(date, inSameDayAs: anchorDate) {
            clock = "\("Timeline.yesterday".localized) \(clock)"
        }

        let text = NSMutableAttributedString(string: clock, attributes: primary)
        let relative = hoursAgo == 0
            ? "Timeline.latest".localized
            : String(format: "Timeline.hours_ago".localized, hoursAgo)
        text.append(NSAttributedString(string: "  \(relative)", attributes: secondary))
        return text
    }
}

/// The hour ticks, their clock labels and the thumb. Index 0 is 24 hours ago
/// at the left; index 24 is the latest reading at the right.
final class MapTimelineTrack: UIView {
    enum Phase { case began, changed, ended }

    var onScrub: ((Int, Phase) -> Void)?
    /// VoiceOver swipe up (+1, later) or down (-1, earlier).
    var onAccessibilityStep: ((Int) -> Void)?

    var anchor: String? {
        didSet { rebuildLabels() }
    }

    static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private let steps = MapHistoryStore.hours
    private let trackY: CGFloat = 13
    private let thumbSize: CGFloat = 18
    private var index = MapHistoryStore.hours

    private let thumb = UIView()
    private var tickLabels: [(index: Int, label: UILabel)] = []
    /// Ticks that carry a label, drawn taller.
    private var majorTicks: Set<Int> = [MapHistoryStore.hours]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .clear
        contentMode = .redraw

        thumb.isUserInteractionEnabled = false
        thumb.backgroundColor = .white
        thumb.layer.cornerRadius = thumbSize / 2
        thumb.layer.borderColor = IndexSelectorView.accent.cgColor
        thumb.layer.borderWidth = 4
        thumb.layer.shadowColor = UIColor.black.cgColor
        thumb.layer.shadowOffset = CGSize(width: 0, height: 1)
        thumb.layer.shadowRadius = 2
        thumb.layer.shadowOpacity = 0.25
        addSubview(thumb)

        // A zero-duration long press reports touch-down, drag and lift alike, so
        // a tap jumps to an hour and a drag scrubs, with one handler.
        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        press.minimumPressDuration = 0
        addGestureRecognizer(press)

        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = "Timeline.accessibility_label".localized

        rebuildLabels()
    }

    func setIndex(_ newIndex: Int, animated: Bool) {
        index = min(max(newIndex, 0), steps)
        let layout = {
            self.layoutThumb()
            self.setNeedsDisplay()
        }
        if animated {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: layout)
        } else {
            layout()
        }
    }

    // MARK: Layout

    /// Inset so the thumb at either end stays inside the bar.
    private var trackRect: CGRect {
        bounds.insetBy(dx: thumbSize / 2 + 2, dy: 0)
    }

    private func x(for index: Int) -> CGFloat {
        trackRect.minX + trackRect.width * CGFloat(index) / CGFloat(steps)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutThumb()

        for (index, label) in tickLabels {
            label.sizeToFit()
            var frame = label.frame
            frame.origin.y = trackY + 9
            frame.origin.x = x(for: index) - frame.width / 2
            // The end label ("現在") hangs left of its tick rather than off the bar.
            frame.origin.x = min(max(frame.origin.x, 0), bounds.width - frame.width)
            label.frame = frame
        }
    }

    private func layoutThumb() {
        thumb.frame = CGRect(
            x: x(for: index) - thumbSize / 2,
            y: trackY - thumbSize / 2,
            width: thumbSize,
            height: thumbSize
        )
    }

    /// One label every six hours on the clock — the date at midnight — plus
    /// "現在" at the right end. Hours too close to either end are left
    /// unlabelled so nothing overlaps.
    private func rebuildLabels() {
        tickLabels.forEach { $0.label.removeFromSuperview() }
        tickLabels = []
        majorTicks = [steps]

        var entries: [(Int, String)] = [(steps, "Timeline.now".localized)]

        if let anchor, let anchorDate = MapTimeline.date(anchor) {
            for index in 3...(steps - 3) {
                let date = anchorDate.addingTimeInterval(-Double(steps - index) * 3600)
                let hour = MapTimeline.calendar.component(.hour, from: date)
                guard hour % 6 == 0 else { continue }
                let text = hour == 0
                    ? Self.dayFormatter.string(from: date)
                    : Self.clockFormatter.string(from: date)
                entries.append((index, text))
            }
        }

        for (index, text) in entries {
            let label = UILabel()
            label.text = text
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabel
            label.isAccessibilityElement = false
            insertSubview(label, belowSubview: thumb)
            tickLabels.append((index, label))
            majorTicks.insert(index)
        }

        setNeedsLayout()
        setNeedsDisplay()
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        let rail = UIBezierPath(
            roundedRect: CGRect(x: trackRect.minX, y: trackY - 2, width: trackRect.width, height: 4),
            cornerRadius: 2
        )
        UIColor.systemFill.setFill()
        rail.fill()

        // Ticks first, so the filled stretch reads as one bar over them.
        for tick in 0...steps {
            let isMajor = majorTicks.contains(tick)
            let height: CGFloat = isMajor ? 10 : 6
            let line = UIBezierPath(
                roundedRect: CGRect(x: x(for: tick) - 0.5, y: trackY - height / 2, width: 1, height: height),
                cornerRadius: 0.5
            )
            (isMajor ? UIColor.secondaryLabel : UIColor.tertiaryLabel).setFill()
            line.fill()
        }

        // From the selected hour up to now: the stretch the map has stepped back over.
        let selected = x(for: index)
        let filled = UIBezierPath(
            roundedRect: CGRect(x: selected, y: trackY - 2, width: trackRect.maxX - selected, height: 4),
            cornerRadius: 2
        )
        IndexSelectorView.accent.withAlphaComponent(0.55).setFill()
        filled.fill()
    }

    // MARK: Interaction

    @objc private func pressed(_ gesture: UILongPressGestureRecognizer) {
        let phase: Phase
        switch gesture.state {
        case .began: phase = .began
        case .changed: phase = .changed
        case .ended, .cancelled, .failed: phase = .ended
        default: return
        }

        let location = gesture.location(in: self).x
        let fraction = (location - trackRect.minX) / max(trackRect.width, 1)
        let nearest = Int((fraction * CGFloat(steps)).rounded())
        onScrub?(min(max(nearest, 0), steps), phase)
    }

    /// The bar's own hit area is taller than its drawing, so a thumb that lands
    /// a little above or below the rail still scrubs.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -8, dy: -10).contains(point)
    }

    override func accessibilityIncrement() {
        onAccessibilityStep?(1)
    }

    override func accessibilityDecrement() {
        onAccessibilityStep?(-1)
    }
}
