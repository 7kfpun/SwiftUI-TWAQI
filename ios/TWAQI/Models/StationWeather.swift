//
//  StationWeather.swift
//  TWAQI
//
//  Created by kf on 5/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// `weather/latest.json` on the webcam host, written hourly by the Worker from
/// two Central Weather Administration (CWA) open-data sets (FOX-11):
///
/// - `forecast`: F-C0032-001, the 36-hour forecast per county (縣市), in
///   12-hour periods: CWA weather code and text, chance of rain, min/max °C.
/// - `observations`: O-A0003-001, the latest readings of CWA's staffed
///   stations, with their WGS84 position.
///
/// Either section is null until its first good sync; the Worker keeps a
/// section's last good copy when a later fetch fails. The CWA key stays in the
/// Worker. Free text (Wx descriptions, station names) is zh-Hant as CWA
/// publishes it.
struct WeatherFile: Decodable, Equatable {
    static let url = StationCam.baseURL.appendingPathComponent("weather/latest.json")

    let updatedAt: String
    let forecast: Forecast?
    let observations: Observations?

    struct Forecast: Decodable, Equatable {
        /// County name as CWA writes it (`臺北市`, 臺 not 台) → its periods,
        /// oldest first.
        let counties: [String: [WeatherPeriod]]
    }

    struct Observations: Decodable, Equatable {
        let stations: [WeatherObservation]
    }
}

/// One period of the county forecast, usually 12 hours (06–18, 18–06); the
/// first can be shorter.
struct WeatherPeriod: Decodable, Equatable {
    /// ISO 8601 with the Taiwan offset, e.g. `2026-11-05T18:00:00+08:00`.
    let start: String
    let end: String
    /// CWA weather code, 1–42 (`WeatherCode`).
    let wx: Int?
    /// CWA's own description, zh-Hant (「多雲短暫雨」).
    let text: String?
    /// Chance of rain, %.
    let pop: Double?
    let minT: Double?
    let maxT: Double?

    var startDate: Date? { WeatherDates.parse(start) }
    var endDate: Date? { WeatherDates.parse(end) }

    /// Starts in the evening or before dawn, Taiwan time: the icon shows a moon.
    var isNight: Bool {
        guard let startDate = startDate else { return false }
        let hour = WeatherDates.calendar.component(.hour, from: startDate)
        return hour >= 18 || hour < 6
    }
}

/// One CWA weather station's latest reading.
struct WeatherObservation: Decodable, Equatable {
    /// CWA station id (`466920`), unrelated to MOENV's or the AQI API's.
    let id: String
    /// zh-Hant (`臺北`).
    let name: String
    let county: String?
    let lat: Double
    let lon: Double
    /// ISO 8601 with offset.
    let time: String
    /// °C
    let temp: Double?
    /// %
    let humidity: Double?
    /// mm since local midnight.
    let rain: Double?
    /// m/s
    let wind: Double?

    var observedAt: Date? { WeatherDates.parse(time) }
}

/// What the station page's weather card shows. Built by
/// `StationWeatherMatcher`, which returns nil rather than an empty one.
struct StationWeather: Equatable {
    struct Now: Equatable {
        let observation: WeatherObservation
        /// From the AQI station to the CWA station.
        let distanceKm: Double
        let observedAt: Date
    }

    /// Nil when no CWA station with a recent reading is within range.
    let now: Now?
    /// The CWA county the periods are for (zh-Hant).
    let county: String?
    /// Up to `StationWeatherMatcher.periodCount` periods that haven't ended.
    let periods: [WeatherPeriod]
}

/// Joins an AQI station to CWA weather. CWA station ids have nothing to do
/// with MOENV's, so the join is by position (observations) and county name
/// (forecast), as `StationCamMatcher` does for cams.
enum StationWeatherMatcher {
    /// Further than this, a reading says little about the station's weather.
    static let maxDistanceKm = 20.0

    /// CWA's staffed stations report every 10 minutes and the Worker syncs
    /// hourly; a reading older than this means the station or the sync has
    /// stopped, and is not shown as "now".
    static let maxObservationAge: TimeInterval = 3 * 60 * 60

    /// The 36-hour forecast is three 12-hour periods.
    static let periodCount = 3

    /// What to show for a station at `lat`/`lon` in `countyLocal`, or nil when
    /// there is nothing: the card is then hidden.
    static func weather(
        lat: Double,
        lon: Double,
        countyLocal: String?,
        in file: WeatherFile,
        now: Date = Date()
    ) -> StationWeather? {
        let stations = file.observations?.stations ?? []
        let reading = nearest(lat: lat, lon: lon, in: stations, now: now)

        let counties = file.forecast?.counties ?? [:]
        let county = self.county(
            countyLocal: countyLocal,
            nearest: nearest(lat: lat, lon: lon, in: stations, now: nil)?.observation,
            in: Set(counties.keys)
        )
        let periods = county.flatMap { counties[$0] }.map { upcoming($0, now: now) } ?? []

        guard reading != nil || !periods.isEmpty else { return nil }
        return StationWeather(now: reading, county: periods.isEmpty ? nil : county, periods: periods)
    }

    /// The closest station within `maxDistanceKm` with a reading. With `now`,
    /// only readings no older than `maxObservationAge` (and not from the
    /// future) count, so a dead station gives way to a live one further off.
    /// A station without a position (0, 0) has no nearest.
    static func nearest(lat: Double, lon: Double, in stations: [WeatherObservation], now: Date?) -> StationWeather.Now? {
        guard lat != 0 || lon != 0 else { return nil }
        return stations
            .compactMap { station -> StationWeather.Now? in
                guard let observedAt = station.observedAt else { return nil }
                if let now = now, !isFresh(observedAt, now: now) { return nil }
                let km = StationCamMatcher.distanceKm(lat, lon, station.lat, station.lon)
                guard km <= maxDistanceKm else { return nil }
                return StationWeather.Now(observation: station, distanceKm: km, observedAt: observedAt)
            }
            .min { $0.distanceKm < $1.distanceKm }
    }

    /// A reading from the last `maxObservationAge`. A few minutes ahead of the
    /// device clock is tolerated; further ahead is a bad timestamp.
    static func isFresh(_ observedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(observedAt)
        return age <= maxObservationAge && age >= -10 * 60
    }

    /// The station's own county when the forecast has it, else the nearest
    /// CWA station's (a station whose record has no county).
    static func county(countyLocal: String?, nearest: WeatherObservation?, in counties: Set<String>) -> String? {
        for candidate in [countyLocal, nearest?.county] {
            if let name = candidate.map(normalizeCounty), counties.contains(name) {
                return name
            }
        }
        return nil
    }

    /// Periods that haven't ended, oldest first, at most `periodCount`.
    static func upcoming(_ periods: [WeatherPeriod], now: Date) -> [WeatherPeriod] {
        Array(
            periods
                .filter { ($0.endDate ?? .distantPast) > now }
                .sorted { $0.start < $1.start }
                .prefix(periodCount)
        )
    }

    /// CWA writes 臺; MOENV and the AQI API sometimes 台.
    static func normalizeCounty(_ name: String) -> String {
        name
            .replacingOccurrences(of: "台", with: "臺")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// CWA's forecast weather codes (預報產品天氣描述代碼表): 1–42, no 40. Many
/// descriptions share a code, so each code's string here is a summary of its
/// group; in Chinese the card shows CWA's own text when the file has it.
enum WeatherCode {
    static let all: [Int] = Array(1...39) + [41, 42]

    static func localizationKey(_ code: Int) -> String {
        "Weather.wx.\(code)"
    }

    /// The line under a period's icon. Chinese: CWA's own text, else the
    /// code's. English: the code's, or nil for a code this build doesn't
    /// know — free Chinese text is never shown in English.
    static func text(code: Int?, cwaText: String?, chinese: Bool, bundle: Bundle = .appLanguage) -> String? {
        if chinese, let cwaText = cwaText, !cwaText.isEmpty {
            return cwaText
        }
        guard let code = code, all.contains(code) else { return nil }
        let key = localizationKey(code)
        let text = NSLocalizedString(key, bundle: bundle, comment: "")
        return text == key ? nil : text
    }

    /// SF Symbol for a code (all available on iOS 15). Clear and partly
    /// cloudy codes get a moon at night; an unknown code gets a plain cloud.
    static func symbol(code: Int?, night: Bool) -> String {
        guard let code = code else { return "cloud.fill" }
        switch code {
        case 1:
            return night ? "moon.stars.fill" : "sun.max.fill"
        case 2, 3, 4:
            return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case 5, 6, 7:
            return "cloud.fill"
        case 8, 9, 10, 11, 30, 31, 32, 38:
            return "cloud.drizzle.fill"
        case 12, 13, 14, 39:
            return "cloud.rain.fill"
        case 15, 16, 17, 18, 34, 35, 36, 41:
            return "cloud.bolt.rain.fill"
        case 19, 20, 29:
            return night ? "cloud.moon.rain.fill" : "cloud.sun.rain.fill"
        case 21, 22, 33:
            return night ? "cloud.moon.bolt.fill" : "cloud.sun.bolt.fill"
        case 23, 37:
            return "cloud.sleet.fill"
        case 24, 25:
            return night ? "cloud.fog.fill" : "sun.haze.fill"
        case 26, 27, 28:
            return "cloud.fog.fill"
        case 42:
            return "snowflake"
        default:
            return "cloud.fill"
        }
    }
}

/// Weather times are Taiwan time; the file carries ISO 8601 with an offset.
enum WeatherDates {
    static let taipei = TimeZone(identifier: "Asia/Taipei")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = taipei
        return calendar
    }

    /// `2026-11-05T18:00:00+08:00` or `…Z`; a value without an offset is
    /// read as Taiwan time.
    static func parse(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) {
            return date
        }
        return localFormatter.date(from: String(value.replacingOccurrences(of: " ", with: "T").prefix(19)))
    }

    /// The Taiwan calendar day a period starts on, `yyyy-MM-dd`, for
    /// `AqiForecastDates.daysFromToday`.
    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private static let localFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = taipei
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = taipei
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
