//
//  PollutantHistoryCache.swift
//  TWAQI
//
//  Created by kf on 21/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// Last good hourly history of each station, on disk, so the station screen's
/// charts work offline.
///
/// One file per station, `pollutant-history-{stationId}.json`, in Application
/// Support next to the other offline caches (`OfflineCacheRetention.isCacheFile`
/// names the prefix, so the week-old purge covers it). Each successful history
/// request rewrites the file whole; its modification date is the age. Nothing
/// older than `OfflineCacheRetention.maxAge` is returned.
final class PollutantHistoryCache {
    static let shared = PollutantHistoryCache()

    /// Prefix shared by every file this cache writes, for the retention purge.
    static let fileNamePrefix = "pollutant-history-"

    static func fileName(stationId: Int) -> String {
        "\(fileNamePrefix)\(stationId).json"
    }

    private let directory: URL
    private let now: () -> Date
    private let queue = DispatchQueue(label: "com.kfpun.twaqi.PollutantHistoryCache")

    init(
        directory: URL = PollutantCache.defaultDirectory,
        now: @escaping () -> Date = Date.init
    ) {
        self.directory = directory
        self.now = now
    }

    /// Saves a successful history. An empty one is not saved: it would wipe
    /// the last good copy.
    func save(_ readings: HistoricalPollutants, stationId: Int) {
        guard !readings.isEmpty, let data = try? JSONEncoder().encode(readings) else { return }
        queue.async {
            try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            try? data.write(to: self.file(stationId), options: .atomic)
        }
    }

    /// The saved history, or nil when there is none younger than a week.
    func readings(stationId: Int) -> HistoricalPollutants? {
        queue.sync {
            let file = self.file(stationId)
            guard
                !OfflineCacheRetention.isExpired(OfflineCacheRetention.modificationDate(of: file), now: now()),
                let data = try? Data(contentsOf: file),
                let readings = try? JSONDecoder().decode(HistoricalPollutants.self, from: data),
                !readings.isEmpty
            else { return nil }
            return readings
        }
    }

    private func file(_ stationId: Int) -> URL {
        directory.appendingPathComponent(Self.fileName(stationId: stationId))
    }
}
