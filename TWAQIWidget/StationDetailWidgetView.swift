//
//  StationDetailWidgetView.swift
//  TWAQIWidget
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI
import WidgetKit

/// The extra-large (iPad) widget: one station in detail, as much of the
/// station page as fits (FOX-72).
///
/// Header and all indices along the top; the 24-hour trend, the 空品區
/// forecast and the cam along the bottom; one line of health advice under
/// them. Where the widget is too short for all of it, the health advice goes
/// first, then the cam, then the forecast. Header, indices, wind and the
/// trend always stay. Nothing here is interactive.
///
/// Locked (no Pro): every number, the chart and the forecast are blurred; the
/// cam stays as the teaser.
struct StationDetailWidgetView: View {
    let reading: WatchReading
    let type: AirIndexTypes
    let detail: WidgetStationDetail?
    let camFrame: UIImage?
    let isLocked: Bool

    private var forecast: AreaForecast? { detail?.areaForecast() }
    private var cam: WidgetStationDetail.Cam? { camFrame == nil ? nil : detail?.cam }

    var body: some View {
        // The first layout that fits the height. Each drops one more section.
        ViewThatFits(in: .vertical) {
            layout(showsAdvice: true, showsCam: true, showsForecast: true)
            layout(showsAdvice: false, showsCam: true, showsForecast: true)
            layout(showsAdvice: false, showsCam: false, showsForecast: true)
            layout(showsAdvice: false, showsCam: false, showsForecast: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func layout(showsAdvice: Bool, showsCam: Bool, showsForecast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                header
                    .frame(width: 210, alignment: .leading)
                indices
            }

            Divider()

            HStack(alignment: .top, spacing: 16) {
                trend
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                if showsForecast, let forecast = forecast {
                    forecastSection(forecast)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if showsCam, let cam = cam, let camFrame = camFrame {
                    camSection(cam, frame: camFrame)
                        .frame(width: Self.camWidth, alignment: .topLeading)
                }
            }

            if showsAdvice {
                advice
            }
        }
    }

    // MARK: - Header

    /// Name, county and 空品區, the chosen index big with its face and level,
    /// and when it was published.
    private var header: some View {
        let status = reading.status(type)

        return VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: 1) {
                Text(reading.displayName)
                    .font(.headline)
                    .lineLimit(1)
                if let place = placeLine {
                    Text(verbatim: place)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                if status.hasFaceImage {
                    Image(status.getImage())
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "\(type.toString()) \(type.getUnit())".trimmingCharacters(in: .whitespaces))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(verbatim: reading.formatted(type))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .proBlurred(isLocked)
                }
            }

            Text(status.toString())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(status.getForegroundColor()))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(status.getColor()), in: Capsule())

            if let updated = StationDetailFormat.publishTime(reading.publishTime) {
                Label {
                    Text(verbatim: updated)
                } icon: {
                    Image(systemName: "clock")
                }
                .labelStyle(.titleAndIcon)
                .accessibilityLabel(Text("Details.last_updated") + Text(verbatim: " \(updated)"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }

    /// "Taipei City · North"
    private var placeLine: String? {
        let parts = [detail?.displayCounty, detail?.displayArea].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Indices and wind

    private static let rows: [[AirIndexTypes?]] = [
        [.aqi, .pm25, .pm10, .o3],
        [.co, .so2, .no2, nil], // nil: wind
    ]

    private var indices: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Details.pollutants")
            ForEach(0..<Self.rows.count, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<Self.rows[row].count, id: \.self) { column in
                        if let index = Self.rows[row][column] {
                            indexCell(index)
                        } else {
                            windCell
                        }
                    }
                }
            }
        }
    }

    /// A pollutant the station doesn't measure reads 0; it shows as a dash,
    /// as on the station page.
    private func indexCell(_ index: AirIndexTypes) -> some View {
        let value = reading.value(index)
        let hasReading = value > 0
        let status = reading.status(index)
        let isChosen = index == type

        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: index.toString())
                    .font(.caption2.weight(.semibold))
                Text(verbatim: index.getUnit())
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(verbatim: hasReading ? reading.formatted(index) : "—")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(hasReading ? Color(status.getColor()) : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .proBlurred(isLocked)
        }
        .cell(highlight: isChosen && hasReading ? Color(status.getColor()) : nil)
    }

    private var windCell: some View {
        let wind = reading.wind

        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text("Details.wind")
                    .font(.caption2.weight(.semibold))
                if !wind.isCalm {
                    Text(verbatim: wind.compassPoint)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .proBlurred(isLocked)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if wind.isCalm {
                Text("Wind.calm")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.vertical, 2)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    // Points the way the air is going, as on the station page.
                    Image(systemName: "arrow.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(wind.arrowRotation)
                        .foregroundStyle(Color(0x5AC8FA))
                    Text(verbatim: wind.speed.format(f: ".1"))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text(verbatim: "m/s")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .proBlurred(isLocked)
            }
        }
        .cell(highlight: nil)
    }

    // MARK: - Trend

    private var trendValues: [Double] {
        (detail?.history ?? []).suffix(24).map { $0.getValue(airIndexType: type) }
    }

    /// The chosen index over the last 24 hours, and which way it is going.
    private var trend: some View {
        let values = trendValues

        return VStack(alignment: .leading, spacing: 5) {
            sectionLabel(verbatim: "\(type.toString()) · 24h")
            if values.count >= 2 {
                let verdict = TrendVerdict(values: values, airIndexType: type)
                VStack(alignment: .leading, spacing: 1) {
                    Label {
                        Text(verdict.title)
                    } icon: {
                        Image(systemName: verdict.symbol)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(verdict.tint)
                    if !verdict.detail.isEmpty {
                        Text(verbatim: verdict.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .proBlurred(isLocked)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                bars(values)
                    .proBlurred(isLocked)

                HStack {
                    if let first = detail?.history.suffix(24).first,
                       let time = StationDetailFormat.hour(first.publishTime) {
                        Text(verbatim: time)
                    }
                    Spacer(minLength: 0)
                    Text("Details.now")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text("Details.no_trend_data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private static let barsHeight: CGFloat = 32

    /// Bars in each hour's band colour, scaled to the day's own range as on
    /// the station page, so a 60–89 day doesn't draw as a flat wall.
    private func bars(_ values: [Double]) -> some View {
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let range = high - low
        let pad = range > 0 ? range * 0.15 : max(high * 0.05, 0.001)
        let lower = max(0, low - pad)
        let upper = max(high + pad, lower + 0.001)

        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                let fraction = max(0, min(1, (value - lower) / (upper - lower)))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(AirStatuses.checkAirStatus(airIndexType: type, value: value).getColor()))
                    .frame(height: 6 + (Self.barsHeight - 6) * CGFloat(fraction))
            }
        }
        .frame(height: Self.barsHeight, alignment: .bottom)
    }

    // MARK: - Forecast

    /// Today and tomorrow for the station's 空品區, and MOENV's text where
    /// it can be read in the reader's language.
    private func forecastSection(_ forecast: AreaForecast) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 3) {
                sectionLabel("Forecast.title")
                Text(verbatim: "· \(forecast.areaTitle)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ForEach(forecast.days, id: \.forecastDate) { day in
                forecastRow(day)
            }
            if let text = StationDetailFormat.forecastText(forecast) {
                Text(verbatim: text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .proBlurred(isLocked)
            }
        }
    }

    private func forecastRow(_ day: AqiForecast) -> some View {
        let status = day.status

        return HStack(spacing: 6) {
            StationDetailFormat.dayTitle(day.forecastDate)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(minWidth: 40, alignment: .leading)
            Text(verbatim: day.aqi.map(String.init) ?? "—")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color(status.getForegroundColor()))
                .frame(minWidth: 32)
                .padding(.vertical, 2)
                .background(Color(status.getColor()), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .proBlurred(isLocked)
            Group {
                if status == .unknown {
                    Text("Forecast.no_value")
                } else {
                    Text(status.toString())
                }
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .proBlurred(isLocked)
        }
    }

    // MARK: - Cam

    private static let camWidth: CGFloat = 160

    /// The latest frame, with its capture time on it.
    private func camSection(_ cam: WidgetStationDetail.Cam, frame: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("Details.live_cam")
            Image(uiImage: frame)
                .resizable()
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(width: Self.camWidth, height: Self.camWidth * 9 / 16)
                .overlay(alignment: .bottomLeading) {
                    if let time = cam.time.flatMap(StationDetailFormat.camTime) {
                        Text("Details.cam_captured \(time)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    // MARK: - Health advice

    /// The general-public line of the station page's health advice, for AQI.
    private var advice: some View {
        let status = reading.status(.aqi)

        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(status.getColor()))
                .frame(width: 3, height: 12)
            Text("Details.health_advice")
                .font(.caption.weight(.semibold))
            Text(status.getGeneralPublicGuidance())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: - Pieces

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .lineLimit(1)
    }

    private func sectionLabel(verbatim text: String) -> some View {
        Text(verbatim: text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .lineLimit(1)
    }
}

private extension View {
    /// One tile of the indices grid; the widget's chosen index is outlined.
    func cell(highlight: Color?) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(highlight.map { $0.opacity(0.16) } ?? Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(highlight ?? .clear, lineWidth: 1.5)
            )
    }
}

/// Text the extra-large widget derives from the feeds. Taiwan-local values
/// are read and shown in `Asia/Taipei`, whatever the device's zone.
enum StationDetailFormat {
    private static let taipei = TimeZone(identifier: "Asia/Taipei")!

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = .app
        formatter.timeZone = taipei
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    /// `publish_time` carries no zone and is Taiwan local time.
    private static let apiFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = taipei
        return formatter
    }()

    /// `publish_time` "2026-11-04T10:00:00" → "11/4 10:00".
    static func publishTime(_ value: String) -> String? {
        guard let date = apiFormatter.date(from: value) else { return nil }
        return formatter("MdHHmm").string(from: date)
    }

    /// `publish_time` → "10:00", for the chart's first hour.
    static func hour(_ value: String) -> String? {
        guard let date = apiFormatter.date(from: value) else { return nil }
        return formatter("HHmm").string(from: date)
    }

    /// Cam capture time "2026-11-04T10:30:00+08:00" → "10:30".
    static func camTime(_ value: String) -> String? {
        guard let date = ISO8601DateFormatter().date(from: value) else { return nil }
        return formatter("HHmm").string(from: date)
    }

    /// 今天 / 明天, else the weekday, in Taiwan's calendar.
    static func dayTitle(_ forecastDate: String) -> Text {
        switch AqiForecastDates.daysFromToday(forecastDate) {
        case 0: return Text("Forecast.today")
        case 1: return Text("Forecast.tomorrow")
        default:
            let weekday = AqiForecastDates.parseDay(forecastDate).map { formatter("EEE").string(from: $0) }
            return Text(verbatim: weekday ?? forecastDate)
        }
    }

    /// MOENV's text in Chinese, or the Worker's translation (FOX-33) in
    /// another language. Nil without one: the widget can't translate on
    /// device as the app does.
    static func forecastText(_ forecast: AreaForecast) -> String? {
        let locale = Locale.app
        if locale.isChinese { return forecast.content }
        return forecast.translatedContent(locale.language.languageCode?.identifier ?? "en")
    }
}

extension WidgetStationDetail {
    /// A made-up day at the placeholder station (松山), for the widget
    /// gallery and the placeholder: what the size shows before any fetch.
    /// No cam: the gallery has no frame to show.
    static var placeholder: WidgetStationDetail {
        let taipei = TimeZone(identifier: "Asia/Taipei")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = taipei
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:00:00"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = taipei

        let aqi: [Double] = [
            61, 64, 66, 63, 60, 58, 55, 54, 52, 50, 49, 51,
            53, 52, 50, 48, 47, 46, 45, 44, 43, 42, 42, 42,
        ]
        let now = Date()
        let history = aqi.enumerated().map { hour, value in
            HistoricalPollutant(
                aqi: value, pm25: value * 0.25, pm10: value * 0.5, no2: value * 0.3, so2: 1.4,
                co: 0.32, o3: value * 0.7, windDirection: 247, windSpeed: 2.6,
                publishTime: formatter.string(from: now.addingTimeInterval(Double(hour - aqi.count + 1) * 3600))
            )
        }

        let today = AqiForecastDates.today(now: now)
        let tomorrow = AqiForecastDates.today(now: now.addingTimeInterval(86_400))
        let forecast = [
            AqiForecast(area: "北部", forecastDate: today, aqi: 48, majorPollutant: nil, minorPollutant: nil,
                        minorPollutantAqi: nil, content: nil, publishTime: nil),
            AqiForecast(area: "北部", forecastDate: tomorrow, aqi: 72, majorPollutant: "細懸浮微粒",
                        minorPollutant: nil, minorPollutantAqi: nil, content: nil, publishTime: nil),
        ]

        return WidgetStationDetail(
            stationId: WatchReading.placeholder.stationId,
            place: Place(nameLocal: "松山", lat: 25.05, lon: 121.578, county: "Taipei City", countyLocal: "臺北市",
                         area: "North", areaLocal: "北部空品區"),
            history: history,
            forecast: forecast,
            cam: nil
        )
    }
}
