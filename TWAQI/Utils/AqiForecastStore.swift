//
//  AqiForecastStore.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// Fetches and caches the 空品區 forecast from Directus `twaqi_aqi_forecast`.
///
/// The Worker refreshes Directus hourly from MOENV AQF_P_01; the MOENV key never
/// reaches the app. Reads use the app's existing Directus static token, which
/// has read on this collection.
///
/// A cache younger than `ttl` is used without a request. When a refresh fails
/// the last good rows are used instead — callers drop days before today, so a
/// cache from yesterday still shows what is left of that forecast, and an old
/// one shows nothing. A response with no rows counts as a failed refresh: it is
/// never written to disk and doesn't start the TTL.
final class AqiForecastStore {
    static let shared = AqiForecastStore()

    static let collectionPath = "items/twaqi_aqi_forecast"

    /// MOENV publishes a few times a day; the Worker syncs hourly.
    static let ttl: TimeInterval = 30 * 60

    private let session: URLSession
    private let cacheFile: URL
    private let baseURL: String?
    private let token: String?

    private var forecasts: [AqiForecast]?
    private var fetchedAt: Date?
    /// Callers waiting on the request in flight, so a screen opened twice
    /// fetches once.
    private var waiting: [([AqiForecast]) -> Void] = []

    init(
        session: URLSession = .shared,
        cacheFile: URL = AqiForecastStore.defaultCacheFile,
        baseURL: String? = getEnv("DirectusUrl"),
        token: String? = getEnv("DirectusFeedbackToken")
    ) {
        self.session = session
        self.cacheFile = cacheFile
        self.baseURL = baseURL
        self.token = token
    }

    static var defaultCacheFile: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("aqi-forecast.json")
    }

    /// Forecast rows from today on, on the main queue. Empty when nothing has
    /// ever loaded (offline first launch, or Directus not configured).
    func forecasts(completion: @escaping ([AqiForecast]) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))

        if forecasts == nil {
            loadFromDisk()
        }

        if let forecasts = forecasts, let fetchedAt = fetchedAt, Date().timeIntervalSince(fetchedAt) < Self.ttl {
            completion(forecasts)
            return
        }

        guard let request = Self.makeRequest(baseURL: baseURL, token: token, today: AqiForecastDates.today()) else {
            completion(forecasts ?? [])
            return
        }

        waiting.append(completion)
        guard waiting.count == 1 else { return }

        session.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let decoded = ok ? data.flatMap { try? JSONDecoder().decode(AqiForecastResponse.self, from: $0) } : nil

            DispatchQueue.main.async {
                // Only rows count as a successful refresh. An empty `data` or
                // a body that doesn't decode is handled like a failed request:
                // the last good rows stay in memory and on disk, and
                // `fetchedAt` is left alone so the next open asks again rather
                // than sitting on nothing for the whole TTL.
                if let decoded = decoded, !decoded.data.isEmpty, let data = data {
                    self.forecasts = decoded.data
                    self.fetchedAt = Date()
                    try? FileManager.default.createDirectory(
                        at: self.cacheFile.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try? data.write(to: self.cacheFile, options: .atomic)
                }

                let forecasts = self.forecasts ?? []
                let waiting = self.waiting
                self.waiting = []
                waiting.forEach { $0(forecasts) }
            }
        }
        .resume()
    }

    /// `GET /items/twaqi_aqi_forecast` for today onwards, archived rows left out.
    static func makeRequest(baseURL: String?, token: String?, today: String) -> URLRequest? {
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
            URLQueryItem(name: "fields", value: "area,forecast_date,aqi,major_pollutant,minor_pollutant,minor_pollutant_aqi,content,publish_time"),
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

    private func loadFromDisk() {
        guard
            let data = try? Data(contentsOf: cacheFile),
            let decoded = try? JSONDecoder().decode(AqiForecastResponse.self, from: data),
            !decoded.data.isEmpty
        else { return }

        forecasts = decoded.data
        fetchedAt = (try? FileManager.default.attributesOfItem(atPath: cacheFile.path))?[.modificationDate] as? Date
    }
}
