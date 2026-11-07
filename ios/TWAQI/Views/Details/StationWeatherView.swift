//
//  StationWeatherView.swift
//  TWAQI
//
//  Created by kf on 5/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// CWA weather for the station (FOX-11): the nearest CWA station's latest
/// reading, then the county's next three forecast periods.
///
/// Sits with the AQI forecast and above the cam: what the air is doing next,
/// the weather driving it, then what it looks like. The caller hides it when
/// `StationWeatherMatcher` has nothing to show.
struct StationWeatherView: View {
    let weather: StationWeather
    /// The station's own county in the app's language (「臺北市」, "Taipei City").
    var countyTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                SectionLabel(text: "Weather.title")
                if let title = headingCounty {
                    Text("· \(title)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                if let now = weather.now {
                    nowRow(now)
                }

                ForEach(Array(weather.periods.enumerated()), id: \.element.start) { index, period in
                    if index > 0 || weather.now != nil {
                        Divider().padding(.leading, 12)
                    }
                    periodRow(period)
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: AreaForecastView.cornerRadius, style: .continuous))
        }
        .padding(.horizontal)
    }

    /// The forecast's county: the station's own name for it, else (in
    /// Chinese) the CWA county it was matched to. Only when there is a
    /// forecast to label.
    private var headingCounty: String? {
        guard !weather.periods.isEmpty else { return nil }
        if let title = countyTitle, !title.isEmpty { return title }
        return Locale.isChinese ? weather.county : nil
    }

    // MARK: - Now

    private func nowRow(_ now: StationWeather.Now) -> some View {
        let reading = now.observation

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(Self.temperature(reading.temp))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                    .accessibilityLabel(Text("Weather.temperature \(Self.temperature(reading.temp))"))

                Spacer(minLength: 0)

                HStack(alignment: .top, spacing: 16) {
                    metric("Weather.humidity", value: Self.percent(reading.humidity), icon: "drop.fill")
                    metric("Weather.rain_today", value: Self.millimetres(reading.rain), icon: "umbrella.fill")
                    metric("Weather.wind", value: Self.windSpeed(reading.wind), icon: "wind")
                }
            }

            Text(Self.stationLine(now, at: Date()))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }

    private func metric(_ title: LocalizedStringKey, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(value, systemImage: icon)
                .font(.subheadline.monospacedDigit())
                .labelStyle(CompactIconLabelStyle())
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: - Forecast

    private func periodRow(_ period: WeatherPeriod) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.dayTitle(period))
                    .font(.subheadline.weight(.semibold))
                Text(Self.timeRange(period))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 76, alignment: .leading)

            Image(systemName: WeatherCode.symbol(code: period.wx, night: period.isNight))
                .symbolRenderingMode(.multicolor)
                .font(.title3)
                .frame(width: 30)
                .accessibilityHidden(true)

            if let text = WeatherCode.text(code: period.wx, cwaText: period.text, chinese: Locale.isChinese) {
                Text(text)
                    .font(.subheadline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Self.temperatureRange(min: period.minT, max: period.maxT))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Label(Self.percent(period.pop), systemImage: "umbrella.fill")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .labelStyle(CompactIconLabelStyle())
                    .accessibilityLabel(Text("Weather.chance_of_rain \(Self.percent(period.pop))"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Formatting

    /// 今天 / 明天 / 後天, else the weekday, for the Taiwan day the period
    /// starts on. The period running now is 今天, even between 00:00 and
    /// 06:00 when the 18:00–06:00 period started the day before.
    static func dayTitle(_ period: WeatherPeriod, now: Date = Date()) -> String {
        guard let start = period.startDate else { return "" }
        if start <= now, let end = period.endDate, now < end {
            return "Forecast.today".localized
        }
        return AreaForecastView.dayTitle(WeatherDates.day(start), now: now)
    }

    /// 「18:00–06:00」, Taiwan time. A period that ends on another Taiwan day
    /// than it starts gets the start date in front (「11/4 18:00–06:00」), so
    /// the night in progress reads differently from tonight's.
    static func timeRange(_ period: WeatherPeriod) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = WeatherDates.taipei
        formatter.dateFormat = "HH:mm"
        let start = period.startDate.map(formatter.string(from:)) ?? "—"
        let end = period.endDate.map(formatter.string(from:)) ?? "—"
        var text = "\(start)–\(end)"
        if let from = period.startDate, let to = period.endDate,
           WeatherDates.day(from) != WeatherDates.day(to) {
            formatter.dateFormat = "M/d"
            text = "\(formatter.string(from: from)) \(text)"
        }
        return text
    }

    /// 「24°」, rounded; 「—」 when missing.
    static func temperature(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°" } ?? "—"
    }

    /// 「21–27°」; one side missing shows just the other.
    static func temperatureRange(min: Double?, max: Double?) -> String {
        switch (min, max) {
        case let (min?, max?):
            return "\(Int(min.rounded()))–\(Int(max.rounded()))°"
        case let (value?, nil), let (nil, value?):
            return temperature(value)
        default:
            return "—"
        }
    }

    static func percent(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    static func millimetres(_ value: Double?) -> String {
        value.map { String(format: "%.1f mm", $0) } ?? "—"
    }

    static func windSpeed(_ value: Double?) -> String {
        value.map { String(format: "%.1f m/s", $0) } ?? "—"
    }

    /// 「臺北測站，距離 2.3 公里 · 觀測於 20 分鐘前」. The station's name is
    /// CWA's Chinese and is only shown in Chinese.
    static func stationLine(_ now: StationWeather.Now, at date: Date) -> String {
        let distance = distanceFormatter.string(from: Measurement(value: now.distanceKm, unit: UnitLength.kilometers))
        let station = Locale.isChinese
            ? String(format: "Weather.station_named %@ %@".localized, now.observation.name, distance)
            : String(format: "Weather.station_nearby %@".localized, distance)
        let age = relativeFormatter.localizedString(for: min(now.observedAt, date), relativeTo: date)
        return "\(station) · \(String(format: "Weather.observed %@".localized, age))"
    }

    // Built per use so they follow a language changed under Help.
    private static var distanceFormatter: MeasurementFormatter {
        let formatter = MeasurementFormatter()
        formatter.locale = .app
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        formatter.numberFormatter.maximumFractionDigits = 1
        formatter.numberFormatter.minimumFractionDigits = 1
        return formatter
    }

    private static var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .app
        formatter.unitsStyle = .short
        return formatter
    }
}

/// Icon and text close together, for the card's small readings.
private struct CompactIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .imageScale(.small)
                .foregroundColor(.secondary)
            configuration.title
        }
    }
}
