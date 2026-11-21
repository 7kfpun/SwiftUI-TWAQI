//
//  DetailsHistoryView.swift
//  TWAQI
//
//  Created by kf on 13/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

/// The last 24 hours or 7 days of air quality, answering one question: is it
/// getting better or worse? Drag the chart to read an exact value and time.
///
/// Defaults to AQI and follows whichever pollutant the reader taps in
/// `StationInfoView`. That selection is passed in and held by the station
/// screen — unlike the old segmented picker, which wrote to the *global*
/// `airIndexTypeSelected` and so silently re-scored every marker on the map.
struct DetailsHistoryView: View {
    var historicalPollutants: HistoricalPollutants
    var airIndexType: AirIndexTypes = .aqi
    /// The readings are the saved copy, because the latest request failed.
    var isCached = false

    @State private var range: HistoryRange = .day
    @State private var selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if dayValues.count >= 2 {
                // Names what the chart is showing — without it, tapping a
                // pollutant above changes the bars with nothing to say why.
                Text(verbatim: airIndexType.toString())
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                headline
                rangePicker
                if series.isChartable {
                    readout
                    chart
                    footnote
                } else {
                    Text("Details.no_trend_data")
                        .font(.callout)
                        .fontWeight(.light)
                        .foregroundColor(.secondary)
                }
                notes
            } else {
                Text("Details.no_trend_data")
                    .font(.callout)
                    .fontWeight(.light)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Verdict

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: trend.symbol)
                .font(.headline)
                .foregroundColor(trend.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(trend.title)
                    .font(.headline)
                    .foregroundColor(trend.tint)

                Text(trend.detail)
                    .font(.caption)
                    .fontWeight(.light)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Chart

    private var rangePicker: some View {
        Picker(selection: $range, label: Text("Details.history_range_label")) {
            Text("Details.history_range_24h").tag(HistoryRange.day)
            Text("Details.history_range_7d").tag(HistoryRange.week)
        }
        .pickerStyle(SegmentedPickerStyle())
        .onChange(of: range) { _ in selected = nil }
    }

    /// The hour under the finger, or the latest one at rest.
    private var readout: some View {
        let sample = selected.flatMap { series.samples.indices.contains($0) ? series.samples[$0] : nil } ?? series.latest
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let value = sample?.value {
                Text(value.format(f: airIndexType.getFormat()))
                    .font(.title3.weight(.medium))
                    .foregroundColor(Color(AirStatuses.checkAirStatus(airIndexType: airIndexType, value: value).getColor()))
                Text(airIndexType.getUnit())
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Details.history_no_reading")
                    .font(.title3.weight(.medium))
                    .foregroundColor(.secondary)
            }
            if let time = sample?.time {
                Text(verbatim: PollutantHistoryFormat.hour(time))
                    .font(.caption)
                    .fontWeight(.light)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .accessibilityHidden(true)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            PollutantHistoryChart(series: series, airIndexType: airIndexType, selected: $selected)

            // Three anchors only — a label per hour is noise.
            HStack {
                Text(verbatim: axisLabel(at: 0))
                Spacer()
                Text(verbatim: axisLabel(at: series.samples.count / 2))
                Spacer()
                Text("Details.now")
            }
            // `.font(_:.weight)` rather than `.fontWeight`, which is iOS 16+.
            .font(.caption2.weight(.light))
            .foregroundColor(.secondary)
            .accessibilityHidden(true)
        }
    }

    /// When the data was last updated, that it is a saved copy, and what the
    /// 7-day range is missing.
    private var notes: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let latest = series.latest {
                Text(String(
                    format: NSLocalizedString("Details.history_updated %@", bundle: .appLanguage, comment: ""),
                    PollutantHistoryFormat.hour(latest.time)
                ))
            }
            if isCached {
                Text("Details.history_offline")
            }
            if range == .week, series.isShorterThanRange, series.isChartable {
                Text(String(
                    format: NSLocalizedString("Details.history_short %d", bundle: .appLanguage, comment: ""),
                    series.coveredHours
                ))
            }
        }
        .font(.caption2.weight(.light))
        .foregroundColor(.secondary)
    }

    private var footnote: some View {
        HStack(spacing: 12) {
            summaryItem("Details.low", value: lowest)
            summaryItem("Details.high", value: highest)
            summaryItem("Details.average", value: average)
            Spacer()
        }
    }

    private func summaryItem(_ key: LocalizedStringKey, value: Double) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption)
                .fontWeight(.light)
                .foregroundColor(.secondary)

            Text(value.format(f: airIndexType.getFormat()))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(Color(AirStatuses.checkAirStatus(
                    airIndexType: airIndexType,
                    value: value
                ).getColor()))
        }
    }

    // MARK: - Data

    private var series: PollutantHistorySeries {
        PollutantHistorySeries.make(readings: historicalPollutants, airIndexType: airIndexType, range: range)
    }

    /// Readings of the last 24 hours, for the verdict: it judges today, whichever
    /// range is on screen.
    private var dayValues: [Double] {
        PollutantHistorySeries.make(readings: historicalPollutants, airIndexType: airIndexType, range: .day).values
    }

    private var values: [Double] { series.values }

    private var lowest: Double { values.min() ?? 0 }
    private var highest: Double { values.max() ?? 0 }
    private var average: Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Trend

    private var trend: TrendVerdict {
        TrendVerdict(values: dayValues, airIndexType: airIndexType)
    }

    private func axisLabel(at index: Int) -> String {
        guard series.samples.indices.contains(index) else { return "" }
        let time = series.samples[index].time
        // A week spans days, so the hour alone would be ambiguous.
        return range == .day ? Self.hourOfDay(time) : PollutantHistoryFormat.hour(time)
    }

    private static func hourOfDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = .taipei
        return formatter.string(from: date)
    }

    init(historicalPollutants: HistoricalPollutants, airIndexType: AirIndexTypes = .aqi, isCached: Bool = false) {
        self.historicalPollutants = historicalPollutants
        self.airIndexType = airIndexType
        self.isCached = isCached
    }
}

/// Presentation for the computed trend: getting better, worse or steady. The
/// judgement itself lives in `AqiTrend` so it can be tested. Shared with the
/// extra-large Home Screen widget (FOX-72).
///
/// The icons carry good-or-bad, not up-or-down. Direction arrows read
/// backwards here: falling AQI is *good* news, so a down arrow beside
/// "Improving" made readers double-take. The title and the detail line
/// already state the direction in words.
struct TrendVerdict {
    var title: LocalizedStringKey
    var detail: String
    var symbol: String
    var tint: Color

    init(values: [Double], airIndexType: AirIndexTypes) {
        self = Self.make(values: values, airIndexType: airIndexType)
    }

    private init(title: LocalizedStringKey, detail: String, symbol: String, tint: Color) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.tint = tint
    }

    private static func make(values: [Double], airIndexType: AirIndexTypes) -> TrendVerdict {
        guard let result = AqiTrend.from(values: values, airIndexType: airIndexType) else {
            return TrendVerdict(
                title: "Details.trend_steady",
                detail: "",
                symbol: "equal.circle.fill",
                tint: .secondary
            )
        }

        switch result.direction {
        case .steady:
            return TrendVerdict(
                title: "Details.trend_steady",
                detail: steadyDetail(result, airIndexType),
                symbol: "equal.circle.fill",
                tint: .secondary
            )

        case .improving:
            return TrendVerdict(
                title: "Details.trend_improving",
                detail: changeDetail("Details.trend_improving_detail", result, airIndexType),
                symbol: "checkmark.circle.fill",
                tint: Color(AirStatuses.good.getColor())
            )

        case .worsening:
            return TrendVerdict(
                title: "Details.trend_worsening",
                detail: changeDetail("Details.trend_worsening_detail", result, airIndexType),
                symbol: "exclamationmark.circle.fill",
                tint: Color(AirStatuses.checkAirStatus(
                    airIndexType: airIndexType,
                    value: result.current
                ).getColor())
            )
        }
    }

    /// The localized detail strings are phrased in whole AQI points, so they
    /// only apply to AQI. Anything measured in ppm rounds to zero there, and is
    /// shown as a value in its own unit instead.
    private static func changeDetail(_ key: String, _ result: AqiTrend, _ airIndexType: AirIndexTypes) -> String {
        guard airIndexType == .aqi else {
            // A bare "0.1 ppb" is true but unreadable — a tenth of a ppb means
            // nothing without the baseline it moved from. Its share of the
            // reading carries the same fact and needs no reference point.
            let baseline = result.direction == .improving
                ? result.current + result.magnitude
                : result.current - result.magnitude
            guard baseline > 0 else {
                return "\(result.magnitude.format(f: airIndexType.getFormat())) \(airIndexType.getUnit())"
            }
            let percent = Int((result.magnitude / baseline * 100).rounded())
            return result.direction == .improving ? "−\(percent)%" : "+\(percent)%"
        }
        return String(format: NSLocalizedString(key, bundle: .appLanguage, comment: ""), result.change)
    }

    private static func steadyDetail(_ result: AqiTrend, _ airIndexType: AirIndexTypes) -> String {
        guard airIndexType == .aqi else {
            return "\(result.current.format(f: airIndexType.getFormat())) \(airIndexType.getUnit())"
        }
        return String(
            format: NSLocalizedString("Details.trend_steady_detail", bundle: .appLanguage, comment: ""),
            Int(result.current.rounded())
        )
    }
}
