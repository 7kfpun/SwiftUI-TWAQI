//
//  WidgetWeather.swift
//  TWAQI
//
//  Created by kf on 8/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// The weather the medium and large Home Screen widgets show for their
/// station (FOX-181): the nearest CWA station's latest reading and the
/// county's current forecast period, from the same `weather/latest.json` the
/// station page reads (FOX-11).
///
/// Everything here is a pure function of the weather file, so it can be
/// tested without a timeline. Weather is free: it is never blurred or locked.
/// Any missing piece shows as 「—」, and none of it can hold back the air
/// quality values.
struct WidgetWeather: Equatable {
    /// °C
    var temperature: Double?
    /// %
    var humidity: Double?
    /// mm since local midnight.
    var rain: Double?
    /// m/s. The AQI station's own wind when it has a direction, else the
    /// CWA station's speed alone: speed and direction always come from one
    /// instrument.
    var windSpeed: Double?
    /// Degrees the wind blows from; nil when calm, unknown, or the speed is
    /// the CWA station's (its open data has no direction).
    var windDirection: Double?
    /// CWA weather code of the current forecast period.
    var code: Int?
    /// CWA's own description of that period, zh-Hant.
    var cwaText: String?
    /// Chance of rain of that period, %.
    var chanceOfRain: Double?
    /// The period is an evening one, for the icon.
    var isNight = false

    /// Whether there is anything to show.
    var isEmpty: Bool {
        temperature == nil && humidity == nil && rain == nil && windSpeed == nil && code == nil
            && cwaText == nil && chanceOfRain == nil
    }

    /// Shown in the widget gallery before any weather is saved.
    static let placeholder = WidgetWeather(
        temperature: 24.3, humidity: 75, rain: 0.5, windSpeed: 3.2, windDirection: 45,
        code: 4, cwaText: "多雲", chanceOfRain: 10
    )

    // MARK: - From the weather file

    /// The weather for a station at `lat`/`lon` in `countyLocal`, or nil when
    /// the file has none in range (`StationWeatherMatcher`) — the widget then
    /// shows 「—」.
    static func make(
        lat: Double?, lon: Double?, countyLocal: String?, windDirection: Double?, windSpeed: Double?,
        in file: WeatherFile?, now: Date = Date()
    ) -> WidgetWeather? {
        guard let file = file, let lat = lat, let lon = lon,
              let station = StationWeatherMatcher.weather(lat: lat, lon: lon, countyLocal: countyLocal, in: file, now: now)
        else { return nil }

        var weather = WidgetWeather()
        if let reading = station.now?.observation {
            weather.temperature = reading.temp
            weather.humidity = reading.humidity
            weather.rain = reading.rain
            weather.windSpeed = reading.wind
        }
        if let speed = windSpeed, speed > 0, let direction = windDirection {
            weather.windSpeed = speed
            weather.windDirection = direction
        }
        if let period = station.periods.first {
            weather.code = period.wx
            weather.cwaText = period.text
            weather.chanceOfRain = period.pop
            weather.isNight = period.isNight
        }
        return weather.isEmpty ? nil : weather
    }

    // MARK: - Formatting

    /// 「24°」, rounded; 「—」 when missing.
    static func temperatureText(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°" } ?? "—"
    }

    static func percentText(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    static func rainText(_ value: Double?) -> String {
        value.map { String(format: "%.1f mm", $0) } ?? "—"
    }

    /// 「3.2 m/s」, with the compass point when the direction is known:
    /// 「NE 3.2 m/s」. 「—」 without a speed.
    static func windText(speed: Double?, direction: Double?) -> String {
        guard let speed = speed else { return "—" }
        let text = String(format: "%.1f m/s", speed)
        guard let direction = direction, speed > 0 else { return text }
        return "\(Wind(direction: direction, speed: speed).compassPoint) \(text)"
    }

    /// The sky in words: CWA's text in Chinese, the code's in English, nil
    /// when the period has neither.
    func skyText(chinese: Bool, bundle: Bundle = .appLanguage) -> String? {
        WeatherCode.text(code: code, cwaText: cwaText, chinese: chinese, bundle: bundle)
    }

    /// SF Symbol for the sky, or a thermometer when only a reading is known.
    var symbol: String {
        code == nil ? "thermometer" : WeatherCode.symbol(code: code, night: isNight)
    }

    /// The large widget's second line: every field but temperature and sky.
    var detailItems: [String] {
        [
            Self.percentText(humidity),
            Self.rainText(rain),
            Self.windText(speed: windSpeed, direction: windDirection),
        ]
    }

    /// The medium widget's one compact line: temperature, wind, sky. Humidity,
    /// rain and chance of rain are dropped: the least useful of the fields
    /// next to the air quality values.
    func compactText(chinese: Bool) -> String {
        var parts = [compactLead]
        if let sky = skyText(chinese: chinese) {
            parts.append(sky)
        }
        return parts.joined(separator: " · ")
    }

    /// The compact line without the sky: temperature and wind, which stay at
    /// full size while a long sky text is truncated.
    var compactLead: String {
        "\(Self.temperatureText(temperature)) · \(Self.windText(speed: windSpeed, direction: windDirection))"
    }

    /// Everything the large row shows, for VoiceOver.
    func spokenText(chinese: Bool) -> String {
        ([Self.temperatureText(temperature), skyText(chinese: chinese)].compactMap { $0 } + detailItems)
            .joined(separator: " · ")
    }
}

/// The weather file the widget saved, in the app group so every widget size
/// reads the same copy and a failed refresh keeps the last good one. It sits
/// in the extra-large widget's cache directory, which the purge at app launch
/// already covers (`OfflineCacheRetention.purge(directory:widgetDirectory:)`).
struct WidgetWeatherCache {
    static let fileName = "cwa-weather.json"

    let directory: URL

    static var shared: WidgetWeatherCache? {
        WidgetStationDetailCache.defaultDirectory.map(WidgetWeatherCache.init(directory:))
    }

    var file: URL { directory.appendingPathComponent(Self.fileName) }

    /// The saved file, unless it was written more than a week ago. Readings
    /// and periods that aged out are dropped by `StationWeatherMatcher`.
    func load(now: Date = Date()) -> WeatherFile? {
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
              now.timeIntervalSince(modified) <= WatchStore.maxReadingAge,
              let data = try? Data(contentsOf: file)
        else { return nil }
        return try? JSONDecoder().decode(WeatherFile.self, from: data)
    }

    func save(_ data: Data) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

enum WidgetWeatherLoader {
    /// Fetches `weather/latest.json` and saves it; on any failure returns the
    /// last saved copy, so the widget never waits on it for long.
    static func refresh(
        cache: WidgetWeatherCache? = .shared, session: URLSession = .shared, url: URL = WeatherFile.url
    ) async -> WeatherFile? {
        if let (data, response) = try? await session.data(for: URLRequest(url: url, timeoutInterval: 10)),
           let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status),
           let file = try? JSONDecoder().decode(WeatherFile.self, from: data) {
            cache?.save(data)
            return file
        }
        return cache?.load()
    }
}
