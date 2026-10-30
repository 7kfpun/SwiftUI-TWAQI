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
