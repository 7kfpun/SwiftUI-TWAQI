//
//  DetailsHistoryView.swift
//  TWAQI
//
//  Created by kf on 13/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftDate
import SwiftUI

/// Last 24 hours of air quality, answering one question: is it getting better
/// or worse?
///
/// Defaults to AQI and follows whichever pollutant the reader taps in
/// `StationInfoView`. That selection is passed in and held by the station
/// screen — unlike the old segmented picker, which wrote to the *global*
/// `airIndexTypeSelected` and so silently re-scored every marker on the map.
struct DetailsHistoryView: View {
    var historicalPollutants: HistoricalPollutants
    var airIndexType: AirIndexTypes = .aqi

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if points.count >= 2 {
                // Names what the chart is showing — without it, tapping a
                // pollutant above changes the bars with nothing to say why.
                Text(verbatim: airIndexType.toString())
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                headline
                chart
                footnote
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

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color(AirStatuses.checkAirStatus(
                            airIndexType: airIndexType,
                            value: point.value
                        ).getColor()))
                        .frame(height: barHeight(for: point.value))
                }
            }
            .frame(height: maxBarHeight, alignment: .bottom)

            // Three anchors only — a label per hour is noise.
            HStack {
                Text(label(at: 0))
                Spacer()
                Text(label(at: points.count / 2))
                Spacer()
                Text("Details.now")
            }
            // `.font(_:.weight)` rather than `.fontWeight`, which is iOS 16+.
            .font(.caption2.weight(.light))
            .foregroundColor(.secondary)
        }
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

    private struct Point {
        var value: Double
        var time: String
    }

    /// Newest last, capped at 24 hours.
    private var points: [Point] {
        let all = historicalPollutants.map {
            Point(value: $0.getValue(airIndexType: airIndexType), time: $0.publishTime)
        }
        return all.count > 24 ? Array(all.suffix(24)) : all
    }

    private var values: [Double] { points.map { $0.value } }

    private var lowest: Double { values.min() ?? 0 }
    private var highest: Double { values.max() ?? 0 }
    private var average: Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Trend

    private struct TrendVerdict {
        var title: LocalizedStringKey
        var detail: String
        var symbol: String
        var tint: Color
    }

    /// Presentation for the computed trend. The judgement itself lives in
    /// `AqiTrend` so it can be tested.
    ///
    /// The icons carry good-or-bad, not up-or-down. Direction arrows read
    /// backwards here: falling AQI is *good* news, so a down arrow beside
    /// "Improving" made readers double-take. The title and the detail line
    /// already state the direction in words.
    private var trend: TrendVerdict {
        // AQI has a meaningful absolute threshold; every other pollutant needs
        // one scaled to its own units.
        let threshold = airIndexType == .aqi
            ? AqiTrend.steadyThreshold
            : AqiTrend.relativeThreshold(for: values)

        guard let result = AqiTrend.from(values: values, steadyThreshold: threshold) else {
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
                detail: steadyDetail(result),
                symbol: "equal.circle.fill",
                tint: .secondary
            )

        case .improving:
            return TrendVerdict(
                title: "Details.trend_improving",
                detail: changeDetail("Details.trend_improving_detail", result),
                symbol: "checkmark.circle.fill",
                tint: Color(AirStatuses.good.getColor())
            )

        case .worsening:
            return TrendVerdict(
                title: "Details.trend_worsening",
                detail: changeDetail("Details.trend_worsening_detail", result),
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
    private func changeDetail(_ key: String, _ result: AqiTrend) -> String {
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
        return String(format: NSLocalizedString(key, comment: ""), result.change)
    }

    private func steadyDetail(_ result: AqiTrend) -> String {
        guard airIndexType == .aqi else {
            return "\(result.current.format(f: airIndexType.getFormat())) \(airIndexType.getUnit())"
        }
        return String(
            format: NSLocalizedString("Details.trend_steady_detail", comment: ""),
            Int(result.current.rounded())
        )
    }

    // MARK: - Geometry

    private let maxBarHeight: CGFloat = 72
    private let minBarHeight: CGFloat = 10

    /// Scaled to the day's own range, padded a little. A zero-baseline axis
    /// renders a 60–89 day as a flat wall of identical bars, which is exactly
    /// what this view is meant to stop doing.
    ///
    /// The padding is a fraction of the range rather than a fixed number of
    /// points: CO spans hundredths of a ppm, so a flat ±5 would swamp the whole
    /// series and flatten every bar.
    private func barHeight(for value: Double) -> CGFloat {
        let range = highest - lowest
        let pad = range > 0 ? range * 0.15 : max(highest * 0.05, 0.001)
        let lower = max(0, lowest - pad)
        let upper = max(highest + pad, lower + 0.001)
        let fraction = (value - lower) / (upper - lower)
        return minBarHeight + (maxBarHeight - minBarHeight) * CGFloat(max(0, min(1, fraction)))
    }

    private func label(at index: Int) -> String {
        guard points.indices.contains(index) else { return "" }
        return points[index].time.toDate()?.toFormat("HH:mm") ?? ""
    }

    init(historicalPollutants: HistoricalPollutants, airIndexType: AirIndexTypes = .aqi) {
        self.historicalPollutants = historicalPollutants
        self.airIndexType = airIndexType
    }
}
