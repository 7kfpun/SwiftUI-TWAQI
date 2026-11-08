//
//  WatchAPI.swift
//  TWAQIWatch
//
//  Created by kf on 20/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import Foundation

/// The pollutant endpoints over plain URLSession.
///
/// Two GETs don't justify a networking library in two watchOS targets, and
/// `Pollutant` is already `Decodable`.
enum WatchAPI {
    enum Failure: Error {
        case badURL
        case badResponse
    }

    /// Home when the reader shares no location: 中正區, Taipei (district office).
    /// No monitoring station is named for or sits in the district, so the
    /// station nearest this point stands in for it.
    static let defaultLocation = CLLocation(latitude: 25.0326, longitude: 121.5199)

    /// Every station in the country, in the API's order (roughly north to south).
    static func currentPollutants(countryCode: String = WatchStore.countryCode) async throws -> Pollutants {
        let response: PollutantsResponse = try await fetch("ApiEnpointCurrentPollutants", ["country": countryCode])
        return response.data
    }

    static func currentPollutant(stationId: Int) async throws -> Pollutant? {
        let response: PollutantsResponse = try await fetch(
            "ApiEnpointCurrentPollutants", ["station_id": String(stationId)]
        )
        return response.data.first
    }

    /// Several stations in one request; the endpoint takes a comma-separated
    /// list, as the iOS Favourites tab sends it.
    static func currentPollutants(stationIds: [Int]) async throws -> Pollutants {
        guard !stationIds.isEmpty else { return [] }
        let data = try await fetchData(
            "ApiEnpointCurrentPollutants", ["station_id": stationIds.map(String.init).joined(separator: ",")]
        )
        return try decodeStations(data)
    }

    /// The API answers HTTP 200 `{"success":false,"error":"No such a station"}`
    /// with no `data` when none of the ids exist. That is a successful
    /// request with no stations, not a failed one, so a widget can tell a
    /// removed station from being offline. Every other error still throws.
    static func decodeStations(_ data: Data) throws -> Pollutants {
        struct Failure: Decodable { let error: String? }
        if let response = try? JSONDecoder().decode(PollutantsResponse.self, from: data) {
            return response.data
        }
        if (try? JSONDecoder().decode(Failure.self, from: data))?.error == "No such a station" {
            return []
        }
        return try JSONDecoder().decode(PollutantsResponse.self, from: data).data
    }

    /// Hourly readings, oldest first.
    static func history(stationId: Int, limit: Int = 24) async throws -> HistoricalPollutants {
        let response: HistoryResponse = try await fetch(
            "ApiEnpointHistoricalPollutants", ["station_id": String(stationId), "limit": String(limit)]
        )
        return response.data.map(\.pollutant)
    }

    static func closest(to location: CLLocation, in stations: Pollutants) -> Pollutant? {
        stations.min { lhs, rhs in
            location.distance(from: CLLocation(latitude: lhs.lat, longitude: lhs.lon))
                < location.distance(from: CLLocation(latitude: rhs.lat, longitude: rhs.lon))
        }
    }

    private static func fetch<Response: Decodable>(
        _ endpointKey: String, _ parameters: [String: String]
    ) async throws -> Response {
        try JSONDecoder().decode(Response.self, from: try await fetchData(endpointKey, parameters))
    }

    private static func fetchData(_ endpointKey: String, _ parameters: [String: String]) async throws -> Data {
        guard
            let domain = getEnv("ApiDomain"),
            let path = getEnv(endpointKey),
            var components = URLComponents(string: domain + path)
        else { throw Failure.badURL }

        // Appended, not replaced: the endpoint may already carry a query string.
        components.percentEncodedQueryItems = (components.percentEncodedQueryItems ?? [])
            + parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw Failure.badURL }

        // URLSession's default waits 60 s for a response, longer than a
        // widget timeline reload is given; fail sooner and fall back to the
        // cached reading instead.
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.badResponse }
        return data
    }
}

/// Lenient like the iOS parser, which defaults every missing reading to 0:
/// a station that doesn't measure a pollutant sends null for it.
private struct HistoryResponse: Decodable {
    struct Point: Decodable {
        let aqi, pm25, pm10, no2, so2, co, o3: Double?
        let windDirection, windSpeed: Double?
        let publishTime: String?

        private enum CodingKeys: String, CodingKey {
            case aqi, pm25, pm10, no2, so2, co, o3
            case windDirection = "wind_direction"
            case windSpeed = "wind_speed"
            case publishTime = "publish_time"
        }

        var pollutant: HistoricalPollutant {
            HistoricalPollutant(
                aqi: aqi ?? 0, pm25: pm25 ?? 0, pm10: pm10 ?? 0, no2: no2 ?? 0, so2: so2 ?? 0,
                co: co ?? 0, o3: o3 ?? 0, windDirection: windDirection ?? 0, windSpeed: windSpeed ?? 0,
                publishTime: publishTime ?? ""
            )
        }
    }

    let data: [Point]
}
