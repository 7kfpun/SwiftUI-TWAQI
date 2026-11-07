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
    /// The Worker's translations of `content` by language code, plus the
    /// source they were made from under `"zh-Hant"`:
    /// `{ "zh-Hant": "今日…", "en": "Today…" }`. Nil on rows not translated
    /// yet, and before the field exists in Directus.
    var contentI18n: [String: String]? = nil

    enum CodingKeys: String, CodingKey {
        case area, aqi, content
        case forecastDate = "forecast_date"
        case majorPollutant = "major_pollutant"
        case minorPollutant = "minor_pollutant"
        case minorPollutantAqi = "minor_pollutant_aqi"
        case publishTime = "publish_time"
        case contentI18n = "content_i18n"
    }

    /// The Worker's translation of `content` into `language` ("en"), only when
    /// it was made from this exact text; nil means fall back to the original
    /// (and on-device translation).
    func translatedContent(_ language: String?) -> String? {
        guard let language = language,
              let source = content?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty,
              let map = contentI18n,
              map[AqiForecast.sourceLanguage]?.trimmingCharacters(in: .whitespacesAndNewlines) == source,
              let text = map[language]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return text
    }

    /// Key in `content_i18n` holding the text the translations were made from.
    static let sourceLanguage = "zh-Hant"

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

extension AqiForecast {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        area = try container.decode(String.self, forKey: .area)
        forecastDate = try container.decode(String.self, forKey: .forecastDate)
        aqi = try container.decodeIfPresent(Int.self, forKey: .aqi)
        majorPollutant = try container.decodeIfPresent(String.self, forKey: .majorPollutant)
        minorPollutant = try container.decodeIfPresent(String.self, forKey: .minorPollutant)
        minorPollutantAqi = try container.decodeIfPresent(Int.self, forKey: .minorPollutantAqi)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        publishTime = try container.decodeIfPresent(String.self, forKey: .publishTime)
        // Optional extra: a malformed map costs the translation, never the row.
        contentI18n = (try? container.decodeIfPresent([String: String].self, forKey: .contentI18n)) ?? nil
    }
}

/// Directus list response: `{ "data": [ … ] }`.
struct AqiForecastResponse: Codable {
    let data: [AqiForecast]
}

/// The read of `twaqi_aqi_forecast`, shared by `AqiForecastStore` and the
/// extra-large widget (FOX-72), which has no store of its own.
enum AqiForecastRequest {
    static let collectionPath = "items/twaqi_aqi_forecast"

    /// `GET /items/twaqi_aqi_forecast` for today onwards, archived rows left out.
    static func make(baseURL: String?, token: String?, today: String) -> URLRequest? {
        guard let baseURL = baseURL?.trimmingCharacters(in: .whitespaces), !baseURL.isEmpty,
              let token = token?.trimmingCharacters(in: .whitespaces), !token.isEmpty,
              let base = URL(string: baseURL),
              var components = URLComponents(url: base.appendingPathComponent(collectionPath), resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "filter[archived][_neq]", value: "true"),
            URLQueryItem(name: "filter[forecast_date][_gte]", value: today),
            // content_i18n only when the field exists and this token may read
            // it: naming it in `fields` before then would fail the whole read.
            URLQueryItem(name: "fields", value: "*"),
            URLQueryItem(name: "sort", value: "forecast_date,area"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
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
        contentDay?.content?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The Worker's translation of `content` into `language`, from the same
    /// row, or nil to show `content` (translated on device if possible).
    func translatedContent(_ language: String?) -> String? {
        contentDay?.translatedContent(language)
    }

    /// The newest-published day with forecast text.
    private var contentDay: AqiForecast? {
        days
            .sorted { ($0.publishTime ?? "") > ($1.publishTime ?? "") }
            .first { !($0.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
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

        let days = Self.days(area: area, in: current, today: today).prefix(limit)
        guard !days.isEmpty else { return nil }

        let nonEmpty = { (value: String?) in value.flatMap { $0.isEmpty ? nil : $0 } }
        let areaTitle = nonEmpty(title) ?? nonEmpty(areaLocal) ?? "\(area)空品區"
        return AreaForecast(areaTitle: areaTitle, days: Array(days))
    }
}

extension AqiForecastMatcher {
    /// Today-onwards days for one MOENV `area`, soonest first, every day the
    /// feed has. One row per day; if the feed somehow has two, the newest
    /// publish wins.
    static func days(area: String, in forecasts: [AqiForecast], today: String) -> [AqiForecast] {
        var byDate: [String: AqiForecast] = [:]
        for row in forecasts where row.area == area && row.forecastDate >= today {
            if let existing = byDate[row.forecastDate], (existing.publishTime ?? "") >= (row.publishTime ?? "") {
                continue
            }
            byDate[row.forecastDate] = row
        }
        return byDate.values.sorted { $0.forecastDate < $1.forecastDate }
    }
}

/// One 空品區 on the Forecast tab (FOX-32).
struct ForecastTabArea: Equatable {
    /// Why the area sits where it does in the list.
    enum Pin: Equatable {
        /// The reader's own area: the nearest station's.
        case reader
        /// First in place of the reader's area: no location, or the nearest
        /// station's area has no forecast. Always 北部.
        case fallback
        /// The area of at least one favourite station.
        case favourite
        case none
    }

    /// MOENV's short name, "北部".
    let area: String
    let pin: Pin
    let forecast: AreaForecast
}

/// Orders every 空品區 for the Forecast tab: the reader's area, then the
/// favourites' areas, then the rest. Pure, so it can be tested without a
/// location or the network.
enum ForecastTabOrdering {
    /// The reader's area when there is no location, or no station near it
    /// matched a forecast area.
    static let fallbackArea = "北部"

    /// MOENV's own order, north to south, then the islands; it orders the
    /// areas that aren't pinned. An area outside this list goes last, by name.
    static let regionOrder = ["北部", "竹苗", "中部", "雲嘉南", "高屏", "宜蘭", "花東", "澎湖", "金門", "馬祖"]

    /// - Parameters:
    ///   - readerArea: the nearest station's MOENV area, already matched; nil
    ///     falls back to `fallbackArea`.
    ///   - favouriteAreas: each favourite station's MOENV area, in favourites
    ///     order; repeats and nils are fine.
    /// - Returns: every area with a forecast from `today` on, each with all
    ///   of its days.
    static func areas(
        forecasts: [AqiForecast],
        readerArea: String?,
        favouriteAreas: [String?],
        today: String,
        chinese: Bool
    ) -> [ForecastTabArea] {
        let available = Set(forecasts.filter { $0.forecastDate >= today }.map(\.area))

        var seen = Set<String>()
        var ordered: [(area: String, pin: ForecastTabArea.Pin)] = []
        func add(_ area: String, _ pin: ForecastTabArea.Pin) {
            guard available.contains(area), seen.insert(area).inserted else { return }
            ordered.append((area, pin))
        }

        if let readerArea = readerArea, available.contains(readerArea) {
            add(readerArea, .reader)
        } else {
            add(fallbackArea, .fallback)
        }
        favouriteAreas.compactMap { $0 }.forEach { add($0, .favourite) }
        let rest = available.sorted { lhs, rhs in
            let left = regionOrder.firstIndex(of: lhs) ?? regionOrder.count
            let right = regionOrder.firstIndex(of: rhs) ?? regionOrder.count
            return left == right ? lhs < rhs : left < right
        }
        rest.forEach { add($0, .none) }

        return ordered.compactMap { entry in
            let days = AqiForecastMatcher.days(area: entry.area, in: forecasts, today: today)
            guard !days.isEmpty else { return nil }
            return ForecastTabArea(
                area: entry.area,
                pin: entry.pin,
                forecast: AreaForecast(areaTitle: title(entry.area, chinese: chinese), days: days)
            )
        }
    }

    /// The text the areas share, when MOENV repeats one national paragraph
    /// on each of them: shown once above the list instead of on every card.
    /// Nil when two areas' texts differ, or fewer than two areas have one.
    static func sharedContent(_ areas: [ForecastTabArea]) -> String? {
        let contents = areas.compactMap(\.forecast.content)
        guard contents.count > 1, Set(contents).count == 1 else { return nil }
        return contents.first
    }

    /// The Worker's translation of `sharedContent` into `language`, from any
    /// area carrying that text, or nil to translate it on device.
    static func sharedTranslation(_ areas: [ForecastTabArea], language: String?) -> String? {
        guard let shared = sharedContent(areas) else { return nil }
        return areas.lazy
            .filter { $0.forecast.content == shared }
            .compactMap { $0.forecast.translatedContent(language) }
            .first
    }

    /// English names as the station API gives them ("North"); the islands,
    /// which the API files under 其他, by their usual names.
    private static let englishNames: [String: String] = [
        "北部": "North",
        "竹苗": "Chu-Miao",
        "中部": "Central",
        "雲嘉南": "Yun-Chia-Nan",
        "高屏": "Kao-Ping",
        "宜蘭": "Yilan",
        "花東": "Hua-Tung",
        "澎湖": "Penghu",
        "金門": "Kinmen",
        "馬祖": "Matsu",
    ]

    private static let islands: Set<String> = ["澎湖", "金門", "馬祖"]

    /// "北部空品區" / "North"; an island is just its name ("金門" / "Kinmen").
    static func title(_ area: String, chinese: Bool) -> String {
        let key = AqiForecastMatcher.normalize(area)
        if chinese {
            return islands.contains(key) ? key : "\(key)空品區"
        }
        return englishNames[key] ?? area
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
        ("臭氧八小時", "O₃ (8h)"),
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
