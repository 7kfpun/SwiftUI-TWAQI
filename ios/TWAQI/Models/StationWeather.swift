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
    /// Degrees clockwise from north the wind blows *from*, 0–360; absent in
    /// files written before the wind layer (TWAQ-15).
    let windDir: Double?
    /// UV index. Only some stations carry a UV sensor, and files written
    /// before TWAQ-14 have none.
    var uv: Double?

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

    /// UV changes slowly across space and few stations measure it, so its
    /// nearest station may be further off than the weather station's.
    static let maxUVDistanceKm = 40.0

    /// The UV index of the closest fresh station that has one within
    /// `maxUVDistanceKm`, or nil. A station without a UV sensor is skipped
    /// rather than ending the search. A station that reads 0 (dusk) is still
    /// the nearest: the chip is then left out (`WeatherChips.minUV`) instead of
    /// borrowing a far station's daytime value for a place that is dark.
    static func nearestUV(lat: Double, lon: Double, in stations: [WeatherObservation], now: Date) -> Double? {
        guard lat != 0 || lon != 0 else { return nil }
        return stations
            .compactMap { station -> (km: Double, uv: Double)? in
                guard
                    let uv = station.uv, uv >= 0,
                    let observedAt = station.observedAt, isFresh(observedAt, now: now)
                else { return nil }
                let km = StationCamMatcher.distanceKm(lat, lon, station.lat, station.lon)
                return km <= maxUVDistanceKm ? (km, uv) : nil
            }
            .min { $0.km < $1.km }?
            .uv
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

/// The compact weather reading on the map's top-left card (TWAQ-6): the
/// nearest CWA station to the map centre, with the county's current forecast
/// period for the condition icon and rain chance.
struct MapCenterWeather: Equatable {
    let temperature: Double?
    /// CWA weather code of the period running now; nil in a gap between
    /// periods, never the next one's.
    let wx: Int?
    /// For the moon variants of the icon, Taiwan time.
    let isNight: Bool
    /// Chance of rain, %, for the period running now.
    let rainChance: Double?
    /// %, from the same station as `temperature`.
    let humidity: Double?
    /// m/s, from the same station as `temperature`.
    let windSpeed: Double?
    /// UV index of the nearest station that measures it (TWAQ-14).
    let uv: Double?
    /// zh-Hant, as CWA publishes it.
    let stationName: String
    /// From the map centre to the CWA station.
    let distanceKm: Double
    let observedAt: Date

    /// Nil when no CWA station with a recent reading is within
    /// `StationWeatherMatcher.maxDistanceKm` of the centre (the sea, abroad),
    /// or the reading has neither a temperature nor a condition.
    static func make(lat: Double, lon: Double, in file: WeatherFile, now: Date = Date()) -> MapCenterWeather? {
        guard
            let weather = StationWeatherMatcher.weather(lat: lat, lon: lon, countyLocal: nil, in: file, now: now),
            let reading = weather.now
        else { return nil }

        let period = weather.periods.first { period in
            guard let start = period.startDate, let end = period.endDate else { return false }
            return start <= now && now < end
        }
        let hour = WeatherDates.calendar.component(.hour, from: now)

        let temperature = reading.observation.temp
        guard temperature != nil || period?.wx != nil else { return nil }

        return MapCenterWeather(
            temperature: temperature,
            wx: period?.wx,
            isNight: period?.isNight ?? (hour >= 18 || hour < 6),
            rainChance: period?.pop,
            humidity: reading.observation.humidity,
            windSpeed: reading.observation.wind,
            uv: StationWeatherMatcher.nearestUV(lat: lat, lon: lon, in: file.observations?.stations ?? [], now: now),
            stationName: reading.observation.name,
            distanceKm: reading.distanceKm,
            observedAt: reading.observedAt
        )
    }

    /// The chips under the AQI on the map card.
    var chips: [WeatherChip] {
        WeatherChips.make(
            temperature: temperature, humidity: humidity, windSpeed: windSpeed,
            rainChance: rainChance, uv: uv
        )
    }
}

// MARK: - Weather chips (TWAQ-14)

/// One small reading under the temperature: chance of rain, feels-like or UV.
struct WeatherChip: Equatable {
    enum Kind: Equatable { case rain, feelsLike, uv }

    let kind: Kind
    /// What the chip shows, 「☂ 10%」, 「Feels 26°」, 「UV 5」.
    let text: String
    /// What VoiceOver reads, with units: 「Chance of rain 10%」.
    let spoken: String
}

/// Builds the chips from raw readings, shared by the map card and the
/// widgets. A reading that is missing leaves its chip out: there is never a
/// dash or an empty chip.
enum WeatherChips {
    /// Below this the UV chip says little (night, heavy cloud) and is left out.
    static let minUV = 1

    /// Apparent temperature in °C, the Australian Bureau of Meteorology's
    /// version of Steadman's formula: `T + 0.33·e − 0.70·ws − 4.00`, with `e`
    /// the water vapour pressure from humidity. Nil unless temperature,
    /// humidity and wind speed are all known (guessing a calm day or a dry
    /// one would mislead).
    static func feelsLike(temperature: Double?, humidity: Double?, windSpeed: Double?) -> Double? {
        guard
            let t = temperature, let rh = humidity, let wind = windSpeed,
            (0...100).contains(rh), wind >= 0
        else { return nil }
        let vapour = rh / 100 * 6.105 * exp(17.27 * t / (237.7 + t))
        return t + 0.33 * vapour - 0.70 * wind - 4.00
    }

    /// The UV chip's category key suffix (WHO bands).
    static func uvBand(_ uv: Int) -> String {
        switch uv {
        case ..<3: return "low"
        case 3...5: return "moderate"
        case 6...7: return "high"
        case 8...10: return "very_high"
        default: return "extreme"
        }
    }

    static func make(
        temperature: Double?, humidity: Double?, windSpeed: Double?, rainChance: Double?, uv: Double?,
        bundle: Bundle = .appLanguage
    ) -> [WeatherChip] {
        func text(_ key: String, _ args: CVarArg...) -> String {
            String(format: NSLocalizedString(key, bundle: bundle, comment: ""), arguments: args)
        }
        var chips: [WeatherChip] = []

        if let chance = rainChance, (0...100).contains(chance) {
            let percent = "\(Int(chance.rounded()))%"
            chips.append(WeatherChip(
                kind: .rain, text: "☂ \(percent)", spoken: text("Weather.chance_of_rain %@", percent)
            ))
        }
        if let feels = feelsLike(temperature: temperature, humidity: humidity, windSpeed: windSpeed) {
            let degrees = "\(Int(feels.rounded()))°"
            chips.append(WeatherChip(
                kind: .feelsLike, text: text("Weather.chip_feels_like %@", degrees),
                spoken: text("Weather.feels_like %@", degrees)
            ))
        }
        if let uv = uv, uv >= 0, uv < 100, Int(uv.rounded()) >= minUV {
            let value = Int(uv.rounded())
            chips.append(WeatherChip(
                kind: .uv, text: text("Weather.chip_uv %@", "\(value)"),
                spoken: text("Weather.uv_index %@ %@", "\(value)", text("Weather.uv.\(uvBand(value))"))
            ))
        }
        return chips
    }
}


// MARK: - Wind layer (TWAQ-15)

/// A CWA station's wind, as the map's arrows layer draws it.
struct WindReading: Equatable {
    let stationId: String
    let name: String
    let lat: Double
    let lon: Double
    /// m/s
    let speed: Double
    /// Meteorological: degrees clockwise from north the wind blows *from*.
    let direction: Double

    var wind: Wind { Wind(direction: direction, speed: speed) }
}

/// The optional wind arrows layer: which CWA readings to draw, how many per
/// zoom, how they look, and the card's "air is coming from…" hint.
enum WindLayer {
    /// UserDefaults key of the toggle. Off until the user turns it on.
    static let defaultsKey = "windLayerOn"

    /// Readings with a usable direction and speed, fresh (same rule as the
    /// weather card), strongest first so thinning keeps the telling ones.
    static func readings(in file: WeatherFile, now: Date = Date()) -> [WindReading] {
        (file.observations?.stations ?? [])
            .compactMap { station -> WindReading? in
                guard
                    let speed = station.wind, speed > 0,
                    let direction = station.windDir, (0...360).contains(direction),
                    let observedAt = station.observedAt,
                    StationWeatherMatcher.isFresh(observedAt, now: now),
                    station.lat != 0 || station.lon != 0
                else { return nil }
                return WindReading(
                    stationId: station.id, name: station.name,
                    lat: station.lat, lon: station.lon,
                    speed: speed, direction: direction.truncatingRemainder(dividingBy: 360)
                )
            }
            .sorted { $0.speed != $1.speed ? $0.speed > $1.speed : $0.stationId < $1.stationId }
    }

    /// Never more arrows than this at once, however far in the user zooms out.
    static let maxMarkers = 40

    /// Side of the grid cell, in degrees, that holds at most one arrow:
    /// about 28 km at zoom 8 (the whole island), shrinking by half per zoom
    /// level until every station has its own cell.
    static func cellDegrees(zoom: Double) -> Double {
        64 / pow(2, max(zoom, 0))
    }

    /// The readings to draw: those in `bounds` (plus a margin), at most one
    /// per grid cell and `maxMarkers` in all. `readings` is strongest first,
    /// so a crowded cell shows its strongest wind.
    static func visible(
        _ readings: [WindReading],
        minLat: Double, maxLat: Double, minLon: Double, maxLon: Double,
        zoom: Double
    ) -> [WindReading] {
        let margin = max(maxLat - minLat, maxLon - minLon) * 0.25
        let cell = cellDegrees(zoom: zoom)
        var taken = Set<[Int]>()
        var out: [WindReading] = []
        for reading in readings {
            guard
                reading.lat >= minLat - margin, reading.lat <= maxLat + margin,
                reading.lon >= minLon - margin, reading.lon <= maxLon + margin
            else { continue }
            let key = [Int((reading.lat / cell).rounded(.down)), Int((reading.lon / cell).rounded(.down))]
            guard taken.insert(key).inserted else { continue }
            out.append(reading)
            if out.count == maxMarkers { break }
        }
        return out
    }

    /// Arrow colour by speed band (the same bands as `Wind.toString`): light
    /// to dark blue, then violet. Separate from the AQI colours, so the layer
    /// never reads as pollution levels.
    static func color(speed: Double) -> UInt32 {
        switch speed {
        case ..<1.6: return 0x8FD3F4
        case ..<3.4: return 0x32ADE6
        case ..<5.5: return 0x0A84FF
        case ..<8.0: return 0x5E5CE6
        default: return 0x8E3FD6
        }
    }

    // MARK: Compass

    /// Eight points, index 0 = north, clockwise.
    static let compassNames = ["north", "north_east", "east", "south_east", "south", "south_west", "west", "north_west"]

    /// 0–7 for a bearing in degrees: 337.5° up to 22.5° is north.
    static func compassIndex(_ bearing: Double) -> Int {
        let positive = bearing.truncatingRemainder(dividingBy: 360)
        let normalised = positive < 0 ? positive + 360 : positive
        return Int((normalised / 45).rounded()) % 8
    }

    /// Initial bearing from one point to another, degrees clockwise from north.
    static func bearing(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> Double {
        let lat1 = fromLat * .pi / 180, lat2 = toLat * .pi / 180
        let dLon = (toLon - fromLon) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Smallest angle between two bearings, 0…180.
    static func angleBetween(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return diff > 180 ? 360 - diff : diff
    }

    // MARK: Hint

    /// Wind below this says nothing about where the air comes from.
    static let hintMinSpeed = 1.5
    /// Stations this close or closer to the centre are the centre's own air.
    static let hintMinKm = 3.0
    static let hintMaxKm = 40.0
    /// Upwind: within this many degrees of the direction the wind comes from.
    static let hintHalfAngle = 45.0
    static let hintMinStations = 2
    /// µg/m³ PM2.5 the upwind average must differ from the centre by.
    static let hintMinDifference = 8.0

    struct Hint: Equatable {
        enum Trend: Equatable { case higher, lower }
        /// Index into `compassNames`: where the air is coming from.
        let fromIndex: Int
        let trend: Trend
    }

    /// "Air is coming from the north-east, where PM2.5 is higher/lower": only
    /// when a fresh CWA wind of at least `hintMinSpeed` is within range of the
    /// map centre, and at least `hintMinStations` AQI stations upwind of it
    /// differ clearly from the centre station. Otherwise nil, never a guess.
    /// `local` is the centre station's PM2.5; `stations` are AQI stations
    /// as (lat, lon, pm25), zero readings excluded by the caller or here.
    static func hint(
        lat: Double,
        lon: Double,
        localPm25: Double,
        stations: [(lat: Double, lon: Double, pm25: Double)],
        in file: WeatherFile,
        now: Date = Date()
    ) -> Hint? {
        guard localPm25 > 0 else { return nil }
        let windy = (file.observations?.stations ?? []).filter { ($0.wind ?? 0) >= hintMinSpeed && $0.windDir != nil }
        guard
            let near = StationWeatherMatcher.nearest(lat: lat, lon: lon, in: windy, now: now),
            let direction = near.observation.windDir, (0...360).contains(direction)
        else { return nil }

        let upwind = stations.compactMap { station -> Double? in
            guard station.pm25 > 0 else { return nil }
            let km = StationCamMatcher.distanceKm(lat, lon, station.lat, station.lon)
            guard km >= hintMinKm, km <= hintMaxKm else { return nil }
            let toward = bearing(fromLat: lat, fromLon: lon, toLat: station.lat, toLon: station.lon)
            return angleBetween(toward, direction) <= hintHalfAngle ? station.pm25 : nil
        }
        guard upwind.count >= hintMinStations else { return nil }

        let difference = upwind.reduce(0, +) / Double(upwind.count) - localPm25
        guard abs(difference) >= hintMinDifference else { return nil }
        return Hint(fromIndex: compassIndex(direction), trend: difference > 0 ? .higher : .lower)
    }

    /// 「Air is coming from the north-east, where PM2.5 is higher」.
    static func hintText(_ hint: Hint, bundle: Bundle = .appLanguage) -> String {
        let point = NSLocalizedString("WindLayer.from.\(compassNames[hint.fromIndex])", bundle: bundle, comment: "")
        let key = hint.trend == .higher ? "WindLayer.hint_higher %@" : "WindLayer.hint_lower %@"
        return String(format: NSLocalizedString(key, bundle: bundle, comment: ""), point)
    }

    /// What VoiceOver reads for an arrow: station, where from, how fast.
    static func accessibilityText(_ reading: WindReading, chinese: Bool = Locale.isChinese, bundle: Bundle = .appLanguage) -> String {
        let point = NSLocalizedString("WindLayer.from.\(compassNames[compassIndex(reading.direction)])", bundle: bundle, comment: "")
        let speed = String(format: "%.1f", reading.speed)
        let description = String(format: NSLocalizedString("WindLayer.arrow %@ %@", bundle: bundle, comment: ""), point, speed)
        // CWA station names are zh-Hant: not read in English.
        return chinese ? "\(reading.name)，\(description)" : description
    }
}
