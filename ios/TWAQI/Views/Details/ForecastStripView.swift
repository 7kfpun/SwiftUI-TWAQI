//
//  ForecastStripView.swift
//  TWAQI
//
//  Created by kf on 22/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// What the strip shows (TWAQ-12): the AQI trend and the weather for the next
/// 24 hours, in one card on the station page opened from the map card.
enum ForecastStripState: Equatable {
    case loading
    case loaded(trend: StripAqiTrend?, cells: [WeatherStripCell])
    /// Nothing to show. `offline` when the station request failed too, so
    /// the message says the data couldn't load rather than that there is none.
    case empty(offline: Bool)

    /// `answered`: the forecast and weather lookups have both finished.
    static func make(
        trend: StripAqiTrend,
        cells: [WeatherStripCell],
        answered: Bool,
        offline: Bool
    ) -> ForecastStripState {
        let chart: StripAqiTrend? = trend.isChartable ? trend : nil
        if chart != nil || !cells.isEmpty {
            return .loaded(trend: chart, cells: cells)
        }
        return answered || offline ? .empty(offline: offline) : .loading
    }
}

struct ForecastStripView: View {
    let state: ForecastStripState
    /// The data shown is a saved copy: the latest request failed.
    var isSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Strip.title")

            VStack(alignment: .leading, spacing: 12) {
                switch state {
                case .loading:
                    loading
                case .empty(let offline):
                    Text(offline ? "Strip.empty_offline" : "Strip.empty")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                case .loaded(let trend, let cells):
                    if isSaved {
                        Label("Strip.saved_note", systemImage: "icloud.slash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let trend = trend {
                        aqiBlock(trend)
                    }
                    if trend != nil, !cells.isEmpty {
                        Divider()
                    }
                    if !cells.isEmpty {
                        weatherBlock(cells)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: AreaForecastView.cornerRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: Self.accessibilitySummary(state, isSaved: isSaved)))
        }
        .padding(.horizontal)
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 6).frame(height: 90)
            RoundedRectangle(cornerRadius: 6).frame(height: 56)
        }
        .foregroundColor(Color(.tertiarySystemFill))
        .accessibilityHidden(true)
        .overlay(ProgressView().accessibilityHidden(true))
    }

    // MARK: AQI

    private func aqiBlock(_ trend: StripAqiTrend) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                legend(title: "Strip.observed", dashed: false)
                if !trend.forecast.isEmpty {
                    legend(title: "Strip.forecast", dashed: true)
                }
                Spacer(minLength: 0)
            }
            StripAqiTrendChart(trend: trend)
                .frame(height: 96)
            if !trend.forecast.isEmpty {
                Text("Strip.aqi_note")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func legend(title: LocalizedStringKey, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : []))
                .frame(width: 14, height: 8)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: Weather

    private func weatherBlock(_ cells: [WeatherStripCell]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.element.start) { _, cell in
                    weatherCell(cell)
                }
            }
            Text("Strip.weather_note")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func weatherCell(_ cell: WeatherStripCell) -> some View {
        VStack(spacing: 4) {
            Text(LocalizedStringKey(cell.part.localizationKey))
                .font(.caption.weight(.semibold))
            // The date of a later day's cell; a blank keeps the row level.
            Text(ForecastStrip.dateLabel(cell) ?? " ")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
            Image(systemName: WeatherCode.symbol(code: cell.wx, night: cell.part.isNight))
                .symbolRenderingMode(.multicolor)
                .font(.title3)
                .frame(height: 26)
            Text(StationWeatherView.temperatureRange(min: cell.minT, max: cell.maxT))
                .font(.caption.weight(.semibold).monospacedDigit())
            Label(StationWeatherView.percent(cell.pop), systemImage: "umbrella.fill")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
    }

    // MARK: VoiceOver

    /// One sentence per row: the AQI trend, then each part of the day.
    static func accessibilitySummary(_ state: ForecastStripState, isSaved: Bool = false, now: Date = Date()) -> String {
        let title = "Strip.title".localized
        switch state {
        case .loading:
            return "\(title). \("Strip.loading".localized)"
        case .empty(let offline):
            return "\(title). \((offline ? "Strip.empty_offline" : "Strip.empty").localized)"
        case .loaded(let trend, let cells):
            var parts = [title]
            if isSaved {
                parts.append("Strip.saved_note".localized)
            }
            if let trend = trend {
                parts.append(aqiSummary(trend))
            }
            parts.append(contentsOf: cells.map { weatherSummary($0, now: now) })
            return parts.joined(separator: ". ")
        }
    }

    static func aqiSummary(_ trend: StripAqiTrend) -> String {
        var sentences: [String] = []
        if let latest = trend.observed.last {
            sentences.append(String(format: "Strip.a11y_observed %d".localized, Int(latest.aqi.rounded())))
        }
        for span in trend.forecast {
            let day = AreaForecastView.dayTitle(span.day, now: trend.now)
            sentences.append(String(format: "Strip.a11y_forecast %@ %d".localized, day, span.aqi))
        }
        return sentences.joined(separator: ", ")
    }

    /// A later day's cell starts with that day ("Tomorrow Morning"), so two
    /// parts of the same name are told apart.
    static func weatherSummary(_ cell: WeatherStripCell, now: Date = Date()) -> String {
        var part = cell.part.localizationKey.localized
        if ForecastStrip.dateLabel(cell, now: now) != nil {
            let day = AreaForecastView.dayTitle(WeatherDates.day(cell.start), now: now)
            part = String(format: "Strip.a11y_day_part %@ %@".localized, day, part)
        }
        let condition = WeatherCode.text(code: cell.wx, cwaText: cell.text, chinese: Locale.isChinese)
        return String(
            format: "Strip.a11y_weather %@ %@ %@ %@".localized,
            part,
            condition ?? "—",
            StationWeatherView.temperatureRange(min: cell.minT, max: cell.maxT),
            StationWeatherView.percent(cell.pop)
        )
    }
}

/// Observed AQI as a line over the last hours, then the forecast days as
/// outlined bars, both in AQI band colours, with a marker at "now". Drawn by
/// hand: Swift Charts needs iOS 16.
private struct StripAqiTrendChart: View {
    let trend: StripAqiTrend

    private let lineWidth: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                ForEach(Array(trend.forecast.enumerated()), id: \.element.day) { _, span in
                    forecastBar(span, size: size)
                }

                ForEach(Array(trend.observedRuns.enumerated()), id: \.offset) { _, run in
                    observedRun(run, size: size)
                }

                // Now
                Path { path in
                    let x = xPosition(trend.now, width: size.width)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                .stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

                Text("Strip.now")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .position(x: min(max(xPosition(trend.now, width: size.width), 14), size.width - 14), y: 6)
            }
        }
    }

    @ViewBuilder
    private func observedRun(_ run: [StripAqiTrend.Point], size: CGSize) -> some View {
        if run.count == 1, let only = run.first {
            Circle().fill(color(only.aqi)).frame(width: 8, height: 8)
                .position(point(only, size: size))
        } else {
            ForEach(Array(zip(run, run.dropFirst()).enumerated()), id: \.offset) { _, pair in
                Path { path in
                    path.move(to: point(pair.0, size: size))
                    path.addLine(to: point(pair.1, size: size))
                }
                .stroke(color(pair.1.aqi), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
    }

    private func forecastBar(_ span: StripAqiTrend.Span, size: CGSize) -> some View {
        let x0 = xPosition(span.start, width: size.width)
        let x1 = xPosition(span.end, width: size.width)
        let y = yPosition(Double(span.aqi), height: size.height)
        let color = color(Double(span.aqi))
        let width = max(x1 - x0 - 2, 2)
        let height = max(size.height - y, 2)
        // A bar too narrow for its number (the last hours of tomorrow) puts
        // the number above itself, kept inside the chart.
        let narrow = width < 34
        return ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(0.28))
                .frame(width: width, height: height)
                .position(x: (x0 + x1) / 2, y: y + height / 2)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: width, height: height)
                .position(x: (x0 + x1) / 2, y: y + height / 2)
            Text("\(span.aqi)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundColor(.primary)
                .fixedSize()
                .position(
                    x: narrow ? min(max((x0 + x1) / 2, 14), size.width - 14) : (x0 + x1) / 2,
                    y: narrow ? max(y - 8, 8) : y + height / 2
                )
        }
    }

    private func color(_ aqi: Double) -> Color {
        Color(AirStatuses.checkAirStatus(airIndexType: .aqi, value: aqi).getColor())
    }

    private var upper: Double {
        let values = trend.observed.map(\.aqi) + trend.forecast.map { Double($0.aqi) }
        return max(100, (values.max() ?? 0) * 1.15)
    }

    private func point(_ point: StripAqiTrend.Point, size: CGSize) -> CGPoint {
        CGPoint(x: xPosition(point.time, width: size.width), y: yPosition(point.aqi, height: size.height))
    }

    private func xPosition(_ date: Date, width: CGFloat) -> CGFloat {
        let total = trend.windowEnd.timeIntervalSince(trend.windowStart)
        guard total > 0 else { return 0 }
        let fraction = date.timeIntervalSince(trend.windowStart) / total
        return width * CGFloat(max(0, min(1, fraction)))
    }

    private func yPosition(_ aqi: Double, height: CGFloat) -> CGFloat {
        let inset = lineWidth + 12
        let fraction = CGFloat(max(0, min(1, aqi / upper)))
        return inset + (height - inset - lineWidth) * (1 - fraction)
    }
}
