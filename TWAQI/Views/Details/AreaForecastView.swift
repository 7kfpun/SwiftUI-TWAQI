//
//  AreaForecastView.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// 空品區預報: MOENV's AQI forecast for the station's air-quality region,
/// today and the next day or two.
///
/// It is a regional outlook, not a reading for this station, so it is labelled
/// with the region and sits below the station's own number. The caller hides
/// it entirely when there is nothing to show.
struct AreaForecastView: View {
    let forecast: AreaForecast

    @State private var expanded = false
    /// Whether the forecast text runs past the collapsed three lines; the
    /// toggle only appears when there is something more to show.
    @State private var truncated = false

    private static let cornerRadius: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                SectionLabel(text: "Forecast.title")
                Text("· \(forecast.areaTitle)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(forecast.days.enumerated()), id: \.element.forecastDate) { index, day in
                    if index > 0 {
                        Divider().padding(.leading, 12)
                    }
                    dayRow(day)
                }

                if let content = forecast.content {
                    Divider()
                    contentText(content)
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))

            caption
        }
        .padding(.horizontal)
    }

    private func dayRow(_ day: AqiForecast) -> some View {
        let status = day.status

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.dayTitle(day.forecastDate))
                    .font(.subheadline.weight(.semibold))
                Text(Self.dateSubtitle(day.forecastDate))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 64, alignment: .leading)

            Text(day.aqi.map(String.init) ?? "—")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundColor(Color(status.getForegroundColor()))
                .frame(minWidth: 44, minHeight: 26)
                .padding(.horizontal, 4)
                .background(Color(status.getColor()))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(status == .unknown ? "Forecast.no_value" : status.toString())
                    .font(.subheadline)
                if let pollutant = day.displayMajorPollutant {
                    Text("Forecast.major_pollutant \(pollutant)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    /// MOENV's forecast text runs to a paragraph per region; show the start
    /// and let the reader open the rest.
    private func contentText(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content)
                .font(.footnote)
                .foregroundColor(.primary)
                .lineLimit(expanded ? nil : Self.collapsedLines)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(truncationProbe(content))
            if truncated {
                Text(expanded ? "Forecast.less" : "Forecast.more")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        // A tap target only when there is more to show; a disabled Button
        // would grey out the text itself.
        .contentShape(Rectangle())
        .onTapGesture {
            guard truncated else { return }
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(truncated ? .isButton : [])
    }

    private static let collapsedLines = 3

    /// Lays the text out at full length and at three lines, invisibly, and
    /// records whether the two differ.
    private func truncationProbe(_ content: String) -> some View {
        GeometryReader { container in
            ZStack {
                measured(content, lines: nil)
                measured(content, lines: Self.collapsedLines)
            }
            .frame(width: container.size.width, alignment: .topLeading)
            .hidden()
        }
        .onPreferenceChange(TextHeightsKey.self) { heights in
            guard heights.count == 2 else { return }
            truncated = (heights.max() ?? 0) > (heights.min() ?? 0) + 1
        }
    }

    private func measured(_ content: String, lines: Int?) -> some View {
        Text(content)
            .font(.footnote)
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: TextHeightsKey.self, value: [proxy.size.height])
            })
    }

    /// 「發布 16:30 · 資料來源：環境部」
    private var caption: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
            if let published = forecast.publishedAt {
                Text("Forecast.published \(Self.publishedText(published))")
            }
            Spacer(minLength: 8)
            Text("Forecast.source")
        }
        .font(.caption.weight(.light))
        .foregroundColor(.secondary)
        .lineLimit(1)
    }

    // MARK: - Formatting

    /// 今天 / 明天 / 後天, else the weekday.
    static func dayTitle(_ forecastDate: String, now: Date = Date()) -> String {
        switch AqiForecastDates.daysFromToday(forecastDate, now: now) {
        case 0: return "Forecast.today".localized
        case 1: return "Forecast.tomorrow".localized
        case 2: return "Forecast.day_after_tomorrow".localized
        default:
            return AqiForecastDates.parseDay(forecastDate).map { weekdayFormatter.string(from: $0) } ?? forecastDate
        }
    }

    /// 「11/1（日）」
    static func dateSubtitle(_ forecastDate: String) -> String {
        AqiForecastDates.parseDay(forecastDate).map { dateFormatter.string(from: $0) } ?? forecastDate
    }

    /// "16:30" when published today (Taiwan time), else "10/30 22:30".
    static func publishedText(_ date: Date, now: Date = Date()) -> String {
        let calendar = AqiForecastDates.calendar
        return calendar.isDate(date, inSameDayAs: now)
            ? timeFormatter.string(from: date)
            : dateTimeFormatter.string(from: date)
    }

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.isChinese ? Locale(identifier: "zh_Hant_TW") : Locale.current
        formatter.timeZone = AqiForecastDates.taipei
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static let weekdayFormatter = formatter("EEEE")
    private static let dateFormatter = formatter("MdEEE")
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = AqiForecastDates.taipei
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = AqiForecastDates.taipei
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct TextHeightsKey: PreferenceKey {
    static var defaultValue: [CGFloat] = []
    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) {
        value.append(contentsOf: nextValue())
    }
}

struct AreaForecastView_Previews: PreviewProvider {
    static let sample: [AqiForecast] = [
        AqiForecast(area: "北部", forecastDate: AqiForecastDates.today(), aqi: 62, majorPollutant: "臭氧8小時",
                    minorPollutant: "細懸浮微粒", minorPollutantAqi: 55,
                    content: "1. 今（31）日東北季風影響，北部擴散條件尚可，偶有短暫普通等級。2. 明日風速減弱，午後臭氧易累積。",
                    publishTime: "2026-10-31 16:30:00"),
        AqiForecast(area: "北部", forecastDate: AqiForecastDates.today(now: Date().addingTimeInterval(86_400)), aqi: 105,
                    majorPollutant: "細懸浮微粒", minorPollutant: nil, minorPollutantAqi: nil, content: nil,
                    publishTime: "2026-10-31 16:30:00"),
        AqiForecast(area: "北部", forecastDate: AqiForecastDates.today(now: Date().addingTimeInterval(2 * 86_400)), aqi: 45,
                    majorPollutant: nil, minorPollutant: nil, minorPollutantAqi: nil, content: nil,
                    publishTime: "2026-10-31 16:30:00"),
    ]

    static var previews: some View {
        AreaForecastView(forecast: AreaForecast(areaTitle: "北部空品區", days: sample))
            .padding(.vertical)
            .previewLayout(.sizeThatFits)
    }
}
