//
//  AqiForecast.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// One day of MOENV's air-quality forecast for one 空品區 (dataset AQF_P_01),
/// as the Worker mirrors it into Directus `twaqi_aqi_forecast`.
///
/// `area` is MOENV's short name ("北部", "雲嘉南"), not the station API's
/// "北部空品區" — `AqiForecastMatcher` joins the two.
struct AqiForecast: Codable, Equatable {
    let area: String
    /// `YYYY-MM-DD`, a Taiwan calendar day.
    let forecastDate: String
    let aqi: Int?
    let majorPollutant: String?
    let minorPollutant: String?
    let minorPollutantAqi: Int?
    let content: String?
    /// Taiwan local time as MOENV publishes it, e.g. `"2026-10-31 16:30:00"`.
    let publishTime: String?

    enum CodingKeys: String, CodingKey {
        case area, aqi, content
        case forecastDate = "forecast_date"
        case majorPollutant = "major_pollutant"
        case minorPollutant = "minor_pollutant"
        case minorPollutantAqi = "minor_pollutant_aqi"
        case publishTime = "publish_time"
    }

    var status: AirStatuses {
        AirStatuses.checkAirStatus(airIndexType: .aqi, value: Double(aqi ?? 0))
    }

    var publishedAt: Date? {
        publishTime.flatMap(AqiForecastDates.parsePublishTime)
    }

    /// Readable major pollutant: MOENV's Chinese name in Chinese, the usual
    /// symbol otherwise. Nil when MOENV names none (normal for 良好 days).
    var displayMajorPollutant: String? {
        majorPollutant.flatMap { AqiForecastPollutant.display($0, chinese: Locale.isChinese) }
    }
}

/// Directus list response: `{ "data": [ … ] }`.
struct AqiForecastResponse: Codable {
    let data: [AqiForecast]
}

/// A station's 空品區 and its forecast days, today onwards.
struct AreaForecast: Equatable {
    /// The station's own area label in the app language, e.g. "北部空品區" or
    /// "North", for the section title.
    let areaTitle: String
    let days: [AqiForecast]

    /// Newest publish time across the days shown.
    var publishedAt: Date? {
        days.compactMap(\.publishedAt).max()
    }

    /// MOENV repeats one forecast text on every row of a publish; show it once.
    var content: String? {
        days
            .sorted { ($0.publishTime ?? "") > ($1.publishTime ?? "") }
            .lazy
            .compactMap { $0.content?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

/// Joins a station's 空品區 to MOENV forecast areas.
enum AqiForecastMatcher {
    /// Station API: "北部空品區", "雲嘉南空品區". MOENV AQF: "北部", "雲嘉南".
    /// Also folds 臺/台 and stray whitespace.
    static func normalize(_ name: String) -> String {
        name
            .replacingOccurrences(of: "臺", with: "台")
            .replacingOccurrences(of: "空品區", with: "")
            .replacingOccurrences(of: "空品", with: "")
            .replacingOccurrences(of: "地區", with: "")
            .filter { !$0.isWhitespace }
    }

    /// The outlying islands are their own forecast areas, but stations there
    /// may carry a catch-all area label, so their county decides.
    private static let islandAreas: [(county: String, area: String)] = [
        ("連江", "馬祖"),
        ("金門", "金門"),
        ("澎湖", "澎湖"),
    ]

    /// The forecast area name in `areas` that this station belongs to, if any.
    static func area(areaLocal: String?, countyLocal: String?, in areas: [String]) -> String? {
        let byKey = Dictionary(areas.map { (normalize($0), $0) }, uniquingKeysWith: { first, _ in first })

        if let areaLocal = areaLocal {
            let key = normalize(areaLocal)
            if !key.isEmpty {
                if let exact = byKey[key] { return exact }
                // "中部" vs "中部地區"-style drift that normalize() didn't catch.
                if let loose = byKey.first(where: { key.hasPrefix($0.key) || $0.key.hasPrefix(key) }) {
                    return loose.value
                }
            }
        }

        if let county = countyLocal.map(normalize), !county.isEmpty,
           let island = islandAreas.first(where: { county.contains($0.county) }) {
            return byKey[normalize(island.area)]
        }
        return nil
    }

    /// Today-onwards days for the station, soonest first, at most `limit`.
    static func forecast(
        areaLocal: String?,
        countyLocal: String?,
        in forecasts: [AqiForecast],
        title: String? = nil,
        today: String = AqiForecastDates.today(),
        limit: Int = 3
    ) -> AreaForecast? {
        let current = forecasts.filter { $0.forecastDate >= today }
        let areas = Array(Set(current.map(\.area))).sorted()
        guard let area = area(areaLocal: areaLocal, countyLocal: countyLocal, in: areas) else { return nil }

        // One row per day; if the feed somehow has two, the newest publish wins.
        var byDate: [String: AqiForecast] = [:]
        for row in current where row.area == area {
            if let existing = byDate[row.forecastDate], (existing.publishTime ?? "") >= (row.publishTime ?? "") {
                continue
            }
            byDate[row.forecastDate] = row
        }
        let days = byDate.values.sorted { $0.forecastDate < $1.forecastDate }.prefix(limit)
        guard !days.isEmpty else { return nil }

        let nonEmpty = { (value: String?) in value.flatMap { $0.isEmpty ? nil : $0 } }
        let areaTitle = nonEmpty(title) ?? nonEmpty(areaLocal) ?? "\(area)空品區"
        return AreaForecast(areaTitle: areaTitle, days: Array(days))
    }
}

/// Dates in this feed are Taiwan calendar days and Taiwan wall-clock times.
enum AqiForecastDates {
    static let taipei = TimeZone(identifier: "Asia/Taipei")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = taipei
        return calendar
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = taipei
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let publishFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = taipei
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Today in Taiwan, `YYYY-MM-DD`.
    static func today(now: Date = Date()) -> String {
        dayFormatter.string(from: now)
    }

    static func parseDay(_ value: String) -> Date? {
        dayFormatter.date(from: String(value.prefix(10)))
    }

    /// "2026-10-31 16:30:00", tolerating a "T" separator and missing seconds.
    static func parsePublishTime(_ value: String) -> Date? {
        var text = value.replacingOccurrences(of: "T", with: " ")
        if text.count == 16 { text += ":00" }
        return publishFormatter.date(from: String(text.prefix(19)))
    }

    /// Whole days from today to `forecastDate`: 0 today, 1 tomorrow.
    static func daysFromToday(_ forecastDate: String, now: Date = Date()) -> Int? {
        guard let day = parseDay(forecastDate), let today = parseDay(today(now: now)) else { return nil }
        return calendar.dateComponents([.day], from: today, to: day).day
    }
}

/// MOENV names pollutants in Chinese ("細懸浮微粒", "臭氧8小時").
enum AqiForecastPollutant {
    /// Most specific first: 細懸浮微粒 contains 懸浮微粒.
    private static let symbols: [(zh: String, symbol: String)] = [
        ("細懸浮微粒", "PM2.5"),
        ("懸浮微粒", "PM10"),
        ("臭氧8小時", "O₃ (8h)"),
        ("臭氧", "O₃"),
        ("二氧化氮", "NO₂"),
        ("二氧化硫", "SO₂"),
        ("一氧化碳", "CO"),
    ]

    static func display(_ raw: String, chinese: Bool) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value != "-" else { return nil }
        if chinese { return value }
        return symbols.first { value.contains($0.zh) }?.symbol ?? value
    }
}
