//
//  ClosestStationView.swift
//  TWAQI
//
//  Created by kf on 9/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SnapKit
import UIKit

/// Floating card on the map showing the station nearest the map centre.
///
/// Layout: identity on the left (name, locality, status, last-updated), the
/// current value pill and health face on the right.
final class ClosestStationView: UIView {
    static let preferredSize = CGSize(width: 232, height: 96)
    /// Extra height while the weather row (TWAQ-6) is shown under the station.
    static let weatherRowHeight: CGFloat = 26
    /// The station and AQI area is tighter while the row is shown, so the
    /// card grows by less than the row (pill 12 + 24, face 8 + 36 fit in it).
    static let topHeightWithWeather: CGFloat = 82
    static var heightWithWeather: CGFloat { topHeightWithWeather + weatherRowHeight }

    private var topHeight: Constraint?

    private var weatherRow: UIView!
    private var weatherIcon: UIImageView!
    private var weatherTempLabel: UILabel!
    private var weatherRainLabel: UILabel!
    private var weatherStationLabel: UILabel!

    private var stack: UIStackView!
    private var skeletonView: UIView!
    private var label: UILabel!
    private var localityLabel: UILabel!
    private var subLabel: UILabel!
    private var updatedLabel: UILabel!
    private var aqiLabel: UILabel!
    private var imageView: UIImageView!

    var stationName: String? {
        get { return label?.text }
        set { label.text = newValue?.maxLength(length: 16) }
    }

    /// Township / county, hidden when the API doesn't supply it.
    var locality: String? {
        get { return localityLabel?.text }
        set {
            localityLabel.text = newValue?.maxLength(length: 22)
            localityLabel.isHidden = (newValue?.isEmpty ?? true)
        }
    }

    var status: String? {
        get { return subLabel?.text }
        set { subLabel.text = newValue?.maxLength(length: 20) }
    }

    /// Raw API `publish_time`; rendered as "Updated HH:mm".
    var publishTime: String? {
        didSet { updateUpdatedLabel() }
    }

    /// Set while the map timeline is scrubbed back, e.g. 「昨天 17:00・24 小時前」.
    /// Replaces the clock-only "Updated HH:mm", which reads the same 24 hours
    /// ago as it does now.
    var timelineContext: String? {
        didSet { updateUpdatedLabel() }
    }

    /// The reading is the last good one saved, because the latest request
    /// failed. Says so with its age instead of a bare clock time, which could
    /// be any day this week.
    var isLastGood = false {
        didSet {
            guard isLastGood != oldValue else { return }
            updateUpdatedLabel()
        }
    }

    /// No reading has arrived yet: grey bars where the name, status and value
    /// will be, rather than an empty card (TWAQ-19).
    var isLoading = false {
        didSet {
            guard isLoading != oldValue else { return }
            skeletonView.isHidden = !isLoading
            stack.isHidden = isLoading
            if isLoading { startSkeletonPulse() } else { skeletonView.layer.removeAllAnimations() }
        }
    }

    /// The request failed and nothing was saved: says so in plain words.
    func showUnavailable() {
        isLoading = false
        label.text = "Offline.card_unavailable".localized
        localityLabel.isHidden = true
        subLabel.text = nil
        updatedLabel.isHidden = true
    }

    private func startSkeletonPulse() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        skeletonView.alpha = 1
        UIView.animate(withDuration: 0.9, delay: 0, options: [.repeat, .autoreverse, .allowUserInteraction]) {
            self.skeletonView.alpha = 0.45
        }
    }

    private func updateUpdatedLabel() {
        if let timelineContext, !timelineContext.isEmpty {
            updatedLabel.isHidden = false
            updatedLabel.text = timelineContext
            updatedLabel.textColor = .label
            return
        }

        if isLastGood, let publishTime, !publishTime.isEmpty {
            updatedLabel.isHidden = false
            updatedLabel.text = String(format: "Offline.updated_ago %@".localized, publishTime.asRelativeAge)
            updatedLabel.textColor = .systemOrange
            return
        }

        guard let publishTime = publishTime, !publishTime.isEmpty else {
            updatedLabel.textColor = .secondaryLabel
            updatedLabel.text = nil
            updatedLabel.isHidden = true
            return
        }
        updatedLabel.isHidden = false
        // Online, but published longer ago than a fresh reading can be.
        if ReadingFreshness.decide(publishTime: publishTime, isFromCache: false) == .stale {
            updatedLabel.text = String(format: "Freshness.stale_short %@".localized, ReadingFreshness.ageText(of: publishTime))
            updatedLabel.textColor = .systemOrange
            return
        }
        updatedLabel.textColor = .secondaryLabel
        updatedLabel.text = "\("Details.last_updated".localized) \(publishTime.asPublishTime)"
    }

    var aqi: String? {
        get { return aqiLabel?.text }
        set { aqiLabel.text = newValue }
    }

    var aqiColor: UIColor? {
        get { return aqiLabel?.backgroundColor }
        set { aqiLabel.backgroundColor = newValue }
    }

    var aqiForegroundColor: UIColor? {
        get { return aqiLabel?.textColor }
        set { aqiLabel.textColor = newValue }
    }

    var image: UIImage? {
        get { return imageView.image }
        set { imageView.image = newValue }
    }

    /// Simple weather for the map centre, the secondary reading under the
    /// AQI. Nil hides the row (outside Taiwan, no recent CWA reading, or the
    /// timeline is scrubbed back).
    var weather: MapCenterWeather? {
        didSet { updateWeatherRow() }
    }

    private func updateWeatherRow() {
        topHeight?.update(offset: weather == nil ? Self.preferredSize.height : Self.topHeightWithWeather)
        guard let weather else {
            weatherRow.isHidden = true
            weatherRow.accessibilityLabel = nil
            return
        }
        weatherRow.isHidden = false

        let config = UIImage.SymbolConfiguration.preferringMulticolor()
        weatherIcon.image = UIImage(
            systemName: WeatherCode.symbol(code: weather.wx, night: weather.isNight),
            withConfiguration: config
        )
        weatherTempLabel.text = Self.temperature(weather.temperature)

        let rain = weather.rainChance.map(Self.percent)
        weatherRainLabel.text = rain.map { "☂ \($0)" }
        weatherRainLabel.isHidden = rain == nil

        weatherStationLabel.text = Self.stationText(name: weather.stationName, distanceKm: weather.distanceKm)

        weatherRow.accessibilityLabel = Self.accessibilityText(weather)
    }

    /// 「24°」, rounded; 「—」 when missing.
    static func temperature(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°" } ?? "—"
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// 「臺北 · 4.2 km」 in Chinese; 「4.2 km away」 in English, where CWA's
    /// Chinese station name is not shown.
    static func stationText(name: String, distanceKm: Double, chinese: Bool = Locale.usesLocalNames) -> String {
        let distance = String(format: "%.1f km", distanceKm)
        return chinese
            ? String(format: "Weather.map_station %@ %@".localized, name, distance)
            : String(format: "Weather.map_station_nearby %@".localized, distance)
    }

    /// Read after the station and AQI (the card's other labels come first):
    /// temperature, condition, chance of rain, then the station.
    static func accessibilityText(_ weather: MapCenterWeather, chinese: Bool = Locale.usesLocalNames) -> String {
        var parts = [String(format: "Weather.temperature %@".localized, temperature(weather.temperature))]
        if let condition = WeatherCode.text(code: weather.wx, cwaText: nil, chinese: false) {
            parts.append(condition)
        }
        if let rain = weather.rainChance {
            parts.append(String(format: "Weather.chance_of_rain %@".localized, percent(rain)))
        }
        parts.append(stationText(name: weather.stationName, distanceKm: weather.distanceKm, chinese: chinese))
        return parts.joined(separator: ", ")
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        createSubviews()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        createSubviews()
    }

    func createSubviews() {
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = .tertiarySystemBackground
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 2
        layer.shadowOpacity = 0.2
        layer.cornerRadius = 10

        // MARK: Right column — value pill + health face
        let rightView = UIView()
        addSubview(rightView)
        rightView.snp.makeConstraints { (make) -> Void in
            make.top.right.equalTo(self)
            topHeight = make.height.equalTo(Self.preferredSize.height).constraint
            make.width.equalTo(72)
        }

        aqiLabel = UILabel()
        aqiLabel.font = .systemFont(ofSize: 13, weight: .medium)
        aqiLabel.textAlignment = .center
        aqiLabel.layer.cornerRadius = 6
        aqiLabel.layer.masksToBounds = true
        rightView.addSubview(aqiLabel)
        aqiLabel.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(rightView).offset(12)
            make.centerX.equalTo(rightView)
            make.height.equalTo(24)
            make.width.greaterThanOrEqualTo(56)
        }

        imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        rightView.addSubview(imageView)
        imageView.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(aqiLabel.snp.bottom).offset(8)
            make.centerX.equalTo(rightView)
            make.height.width.equalTo(36)
        }

        // MARK: Left column — identity
        stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        addSubview(stack)
        stack.snp.makeConstraints { (make) -> Void in
            make.left.equalTo(self).offset(12)
            make.right.equalTo(rightView.snp.left).offset(-4)
            make.centerY.equalTo(rightView)
        }

        label = UILabel()
        label.numberOfLines = 2
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(label)

        localityLabel = UILabel()
        localityLabel.font = .systemFont(ofSize: 11, weight: .light)
        localityLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(localityLabel)

        subLabel = UILabel()
        subLabel.font = .systemFont(ofSize: 12)
        subLabel.textColor = .label
        stack.addArrangedSubview(subLabel)

        updatedLabel = UILabel()
        updatedLabel.font = .systemFont(ofSize: 10, weight: .light)
        updatedLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(updatedLabel)
        stack.setCustomSpacing(5, after: subLabel)

        // MARK: Skeleton — shown in place of both columns while loading
        skeletonView = UIView()
        skeletonView.isHidden = true
        skeletonView.isAccessibilityElement = true
        skeletonView.accessibilityLabel = "Loading.label".localized
        addSubview(skeletonView)
        skeletonView.snp.makeConstraints { (make) -> Void in
            make.top.right.bottom.equalTo(rightView)
            make.left.equalTo(self)
        }
        func bar(width: CGFloat, height: CGFloat, radius: CGFloat) -> UIView {
            let bar = UIView()
            bar.backgroundColor = .quaternarySystemFill
            bar.layer.cornerRadius = radius
            skeletonView.addSubview(bar)
            return bar
        }
        let nameBar = bar(width: 110, height: 14, radius: 4)
        nameBar.snp.makeConstraints { $0.left.equalTo(skeletonView).offset(12); $0.centerY.equalTo(skeletonView).offset(-14); $0.width.equalTo(110); $0.height.equalTo(14) }
        let statusBar = bar(width: 80, height: 12, radius: 4)
        statusBar.snp.makeConstraints { $0.left.equalTo(skeletonView).offset(12); $0.top.equalTo(nameBar.snp.bottom).offset(8); $0.width.equalTo(80); $0.height.equalTo(12) }
        let timeBar = bar(width: 60, height: 10, radius: 4)
        timeBar.snp.makeConstraints { $0.left.equalTo(skeletonView).offset(12); $0.top.equalTo(statusBar.snp.bottom).offset(8); $0.width.equalTo(60); $0.height.equalTo(10) }
        let pillBar = bar(width: 56, height: 24, radius: 6)
        pillBar.snp.makeConstraints { $0.top.equalTo(skeletonView).offset(12); $0.right.equalTo(skeletonView).offset(-8); $0.width.equalTo(56); $0.height.equalTo(24) }
        let faceBar = bar(width: 36, height: 36, radius: 18)
        faceBar.snp.makeConstraints { $0.top.equalTo(pillBar.snp.bottom).offset(8); $0.centerX.equalTo(pillBar); $0.width.equalTo(36); $0.height.equalTo(36) }

        // MARK: Weather row (secondary reading)
        weatherRow = UIView()
        weatherRow.isHidden = true
        weatherRow.isAccessibilityElement = true
        addSubview(weatherRow)
        weatherRow.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(rightView.snp.bottom)
            make.left.equalTo(self).offset(12)
            make.right.equalTo(self).offset(-12)
            make.height.equalTo(Self.weatherRowHeight)
        }

        let separator = UIView()
        separator.backgroundColor = .separator
        weatherRow.addSubview(separator)
        separator.snp.makeConstraints { (make) -> Void in
            make.top.left.right.equalTo(weatherRow)
            make.height.equalTo(1 / UIScreen.main.scale)
        }

        weatherIcon = UIImageView()
        weatherIcon.contentMode = .scaleAspectFit
        weatherRow.addSubview(weatherIcon)
        weatherIcon.snp.makeConstraints { (make) -> Void in
            make.left.centerY.equalTo(weatherRow)
            make.width.height.equalTo(20)
        }

        weatherTempLabel = UILabel()
        weatherTempLabel.font = .systemFont(ofSize: 13, weight: .medium)
        weatherTempLabel.adjustsFontSizeToFitWidth = true
        weatherTempLabel.minimumScaleFactor = 0.7
        weatherTempLabel.setContentHuggingPriority(.required, for: .horizontal)
        weatherTempLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        weatherRow.addSubview(weatherTempLabel)
        weatherTempLabel.snp.makeConstraints { (make) -> Void in
            make.left.equalTo(weatherIcon.snp.right).offset(4)
            make.centerY.equalTo(weatherRow)
        }

        weatherRainLabel = UILabel()
        weatherRainLabel.font = .systemFont(ofSize: 11)
        weatherRainLabel.textColor = .secondaryLabel
        weatherRainLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        weatherRow.addSubview(weatherRainLabel)
        weatherRainLabel.snp.makeConstraints { (make) -> Void in
            make.left.equalTo(weatherTempLabel.snp.right).offset(6)
            make.centerY.equalTo(weatherRow)
        }

        weatherStationLabel = UILabel()
        weatherStationLabel.font = .systemFont(ofSize: 10, weight: .light)
        weatherStationLabel.textColor = .secondaryLabel
        weatherStationLabel.textAlignment = .right
        weatherStationLabel.adjustsFontSizeToFitWidth = true
        weatherStationLabel.minimumScaleFactor = 0.7
        weatherRow.addSubview(weatherStationLabel)
        weatherStationLabel.snp.makeConstraints { (make) -> Void in
            make.left.greaterThanOrEqualTo(weatherRainLabel.snp.right).offset(6)
            make.right.centerY.equalTo(weatherRow)
        }
    }
}
