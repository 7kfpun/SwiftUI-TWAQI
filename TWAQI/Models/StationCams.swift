//
//  StationCams.swift
//  TWAQI
//
//  Created by kf on 30/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// One MOENV station webcam, as listed in the public cam manifest.
///
/// `siteId` is MOENV's zero-padded SiteId ("001" for 基隆). It is *not* the
/// AQI API's `station_id` (基隆 is 91 there) — the two numbering schemes are
/// unrelated, so the only way from a station to its cam is `StationCamMatcher`.
struct StationCam: Equatable {
    static let baseURL = URL(string: "https://twaqi.app.wahthefox.com")!

    let siteId: String
    let name: String
    let lat: Double
    let lon: Double
    /// Capture time, e.g. `"2026-10-30T22:30:00+08:00"`.
    let time: String?

    /// `/stations/001.jpg`, versioned by capture time. The CDN caches each
    /// image for hours, so without the version a fresh frame would sit behind
    /// a stale one until the edge cache expired.
    var imageURL: URL {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("stations/\(siteId).jpg"),
            resolvingAgainstBaseURL: false
        )!
        if let time = time {
            components.queryItems = [URLQueryItem(name: "t", value: time)]
        }
        return components.url!
    }

    var capturedAt: Date? {
        time.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}

/// `manifest.json`: `{ "updatedAt": …, "stations": { "001": { name, lat, lon, time, key } } }`
struct StationCamManifest: Decodable {
    let cams: [StationCam]

    private struct Entry: Decodable {
        let name: String
        let lat: Double
        let lon: Double
        let time: String?
    }

    private enum CodingKeys: String, CodingKey {
        case stations
    }

    init(cams: [StationCam]) {
        self.cams = cams
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let stations = try values.decode([String: Entry].self, forKey: .stations)
        cams = stations
            .map { StationCam(siteId: $0.key, name: $0.value.name, lat: $0.value.lat, lon: $0.value.lon, time: $0.value.time) }
            .sorted { $0.siteId < $1.siteId }
    }
}

/// Joins an AQI station to its MOENV cam.
enum StationCamMatcher {
    /// How far a station may sit from a cam and still be matched by position
    /// alone. Deliberately tight: the closest pair of distinct cam sites is
    /// ~530 m apart (林森 / 臺南), and at 1.5 km 復興 (no cam) picked up 前鎮's
    /// cam 610 m away. Stations whose coordinates drift further than this from
    /// their cam's are still caught by name, which is checked first.
    static let maxDistanceKm = 0.5

    /// Name first, then the nearest cam within `maxDistanceKm`, else nil.
    static func match(name: String, lat: Double, lon: Double, in cams: [StationCam]) -> StationCam? {
        let key = normalize(name)
        if !key.isEmpty, let cam = cams.first(where: { normalize($0.name) == key }) {
            return cam
        }

        guard lat != 0 || lon != 0 else { return nil }
        return cams
            .map { (cam: $0, km: distanceKm(lat, lon, $0.lat, $0.lon)) }
            .filter { $0.km <= maxDistanceKm }
            .min { $0.km < $1.km }?
            .cam
    }

    /// The API and the manifest disagree on trivia: `屏東(琉球)` vs
    /// `屏東（琉球）`, and 臺 vs 台 depending on source.
    static func normalize(_ name: String) -> String {
        name
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "臺", with: "台")
            .filter { !$0.isWhitespace }
    }

    /// Great-circle distance.
    static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let rad = Double.pi / 180
        let dLat = (lat2 - lat1) * rad
        let dLon = (lon2 - lon1) * rad
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * rad) * cos(lat2 * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 6371 * 2 * asin(min(1, sqrt(a)))
    }
}

/// What the station screen knows about its cam.
enum StationCamState: Equatable {
    /// Station or manifest not loaded yet.
    case loading
    case available(StationCam)
    /// No cam joins to this station — most micro-sensor sites.
    case missing
}

/// One clock hour of a cam's history: `stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg`.
///
/// The Worker files the first frame of each Taiwan clock hour (the :00 one
/// whenever a sync catches it) under that key and keeps a week of them, so
/// the app builds the URL itself; nothing lists the bucket.
struct StationCamHour: Hashable {
    let siteId: String
    /// Start of the hour.
    let hour: Date

    /// MOENV capture times are Taiwan clock time (UTC+8, no DST).
    static let timeZone = TimeZone(identifier: "Asia/Taipei")!

    /// The 24 hours the scrubber offers.
    static let count = 24

    /// Slots fetched around the one on screen: it and two either side.
    static let neighbors = 2

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()

    init(siteId: String, hour: Date) {
        self.siteId = siteId
        self.hour = Self.startOfHour(hour)
    }

    /// `"2026-10-30"`
    var day: String {
        let c = Self.calendar.dateComponents([.year, .month, .day], from: hour)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `"22"`
    var hourOfDay: String {
        String(format: "%02d", Self.calendar.component(.hour, from: hour))
    }

    /// `stations/001/2026-10-30/22.jpg` — the R2 key.
    var objectKey: String {
        "stations/\(siteId)/\(day)/\(hourOfDay).jpg"
    }

    /// Not versioned: an hour's frame never changes once filed.
    var imageURL: URL {
        StationCam.baseURL.appendingPathComponent(objectKey)
    }

    /// `001-2026-10-30-22.jpg` — flat, so the offline purge needn't recurse.
    var cacheFileName: String {
        "\(siteId)-\(day)-\(hourOfDay).jpg"
    }

    static func startOfHour(_ date: Date) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }

    /// The 24 clock hours up to and including the one `anchor` falls in,
    /// oldest first.
    ///
    /// The anchor is the live frame's capture time rather than the clock: MOENV
    /// frames land about half an hour late, so the hour that's just begun
    /// would almost always be an empty slot.
    static func slots(siteId: String, anchor: Date) -> [StationCamHour] {
        let last = startOfHour(anchor)
        return (0..<count).reversed().map {
            StationCamHour(siteId: siteId, hour: last.addingTimeInterval(-Double($0) * 3600))
        }
    }

    /// Indices to load around `index`, nearest first: it, then ±1, then ±2,
    /// clamped to `0..<count`. Nothing further out is fetched or decoded.
    static func window(around index: Int, count: Int = count, radius: Int = neighbors) -> [Int] {
        guard (0..<count).contains(index) else { return [] }
        let neighbors = (0..<max(radius, 0)).flatMap { [index - $0 - 1, index + $0 + 1] }
        return [index] + neighbors.filter { (0..<count).contains($0) }
    }
}
