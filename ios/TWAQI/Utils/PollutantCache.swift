//
//  PollutantCache.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// Last good current readings, on disk, for when the AQI API can't be reached.
///
/// `APIManager` saves every successful current-pollutants response here; the
/// map, Favourites and station screens read it back when their own request
/// fails, so offline they show the last readings rather than nothing. Each
/// reading carries its own `publishTime`, which those screens already show,
/// so a stale one says how old it is.
///
/// Two files, in Application Support like `stations-*.json` (Caches can be
/// purged under storage pressure, and these are what keep the app readable
/// offline):
/// - `pollutants-{country}.json`: the country response as the API sent it,
///   for the map.
/// - `pollutants-stations.json`: the newest reading seen for each station,
///   from either endpoint, so a station the map has shown can be opened
///   offline even if its own screen never loaded.
///
/// Nothing older than `OfflineCacheRetention.maxAge` is returned.
final class PollutantCache {
    static let shared = PollutantCache()

    static let stationsFileName = "pollutants-stations.json"

    static func countryFileName(_ countryCode: String) -> String {
        "pollutants-\(countryCode).json"
    }

    /// Prefix shared by every file this cache writes, for the retention purge.
    static let fileNamePrefix = "pollutants-"

    private let directory: URL
    private let now: () -> Date
    /// All state and file IO, so a 65 KB country write never lands on the
    /// main thread and reads never see half a merge.
    private let queue = DispatchQueue(label: "com.kfpun.twaqi.PollutantCache")

    private struct Stored {
        let savedAt: Date
        /// The API's own JSON for the station, so the file decodes with the
        /// same `Pollutant` decoder as a live response.
        let object: [String: Any]
        let pollutant: Pollutant
    }

    /// Station id → newest reading. Loaded from disk on first use.
    private var stations: [Int: Stored]?

    init(directory: URL = PollutantCache.defaultDirectory, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    // MARK: Writing

    /// A successful `current-pollutants?country=` response body.
    func save(countryCode: String, response data: Data) {
        queue.async {
            self.write(data, to: self.directory.appendingPathComponent(Self.countryFileName(countryCode)))
            self.merge(response: data)
        }
    }

    /// A successful `current-pollutants?station_id=` response body.
    func saveStations(response data: Data) {
        queue.async {
            self.merge(response: data)
        }
    }

    // MARK: Reading

    /// The last country response, or nil when there is none younger than a week.
    func pollutants(countryCode: String) -> Pollutants? {
        queue.sync {
            let file = directory.appendingPathComponent(Self.countryFileName(countryCode))
            guard
                !OfflineCacheRetention.isExpired(OfflineCacheRetention.modificationDate(of: file), now: now()),
                let data = try? Data(contentsOf: file),
                let response = try? JSONDecoder().decode(PollutantsResponse.self, from: data),
                !response.data.isEmpty
            else { return nil }
            return response.data
        }
    }

    /// The last reading of each of `stationIds` that has one younger than a
    /// week, in the order asked for.
    func pollutants(stationIds: [Int]) -> Pollutants {
        queue.sync {
            loadStationsIfNeeded()
            let date = now()
            return stationIds.compactMap { id in
                guard let stored = stations?[id],
                      !OfflineCacheRetention.isExpired(stored.savedAt, now: date)
                else { return nil }
                return stored.pollutant
            }
        }
    }

    func pollutant(stationId: Int) -> Pollutant? {
        pollutants(stationIds: [stationId]).first
    }

    // MARK: Private — on `queue`

    private func merge(response data: Data) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let objects = json["data"] as? [[String: Any]]
        else { return }

        loadStationsIfNeeded()
        let savedAt = now()
        var merged = stations ?? [:]
        for object in objects {
            guard let pollutant = Self.decode(object) else { continue }
            merged[pollutant.stationId] = Stored(savedAt: savedAt, object: object, pollutant: pollutant)
        }
        merged = merged.filter { !OfflineCacheRetention.isExpired($0.value.savedAt, now: savedAt) }
        stations = merged

        let file: [String: Any] = [
            "stations": Dictionary(uniqueKeysWithValues: merged.map { id, stored in
                (String(id), [
                    "saved_at": stored.savedAt.timeIntervalSince1970,
                    "pollutant": stored.object,
                ] as [String: Any])
            }),
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: file) else { return }
        write(encoded, to: directory.appendingPathComponent(Self.stationsFileName))
    }

    private func loadStationsIfNeeded() {
        guard stations == nil else { return }
        stations = [:]

        guard
            let data = try? Data(contentsOf: directory.appendingPathComponent(Self.stationsFileName)),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = json["stations"] as? [String: [String: Any]]
        else { return }

        let date = now()
        for entry in entries.values {
            guard
                let savedAt = (entry["saved_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
                !OfflineCacheRetention.isExpired(savedAt, now: date),
                let object = entry["pollutant"] as? [String: Any],
                // A file an older build wrote may no longer decode; skip it.
                let pollutant = Self.decode(object)
            else { continue }
            stations?[pollutant.stationId] = Stored(savedAt: savedAt, object: object, pollutant: pollutant)
        }
    }

    private static func decode(_ object: [String: Any]) -> Pollutant? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(Pollutant.self, from: data)
    }

    private func write(_ data: Data, to file: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
