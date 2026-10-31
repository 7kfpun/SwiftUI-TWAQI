//
//  OfflineCacheRetention.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// The hard ceiling on how old offline data may be and still be shown.
///
/// Each store keeps its own soft TTL for *refreshing* (30 min forecast, 1 h cam
/// manifest, …) and falls back to its last good copy when a refresh fails. This
/// is the limit on that fallback: past a week, a reading says more about the
/// last time the app was online than about the air, so it is discarded rather
/// than shown.
enum OfflineCacheRetention {
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    /// True when `date` is older than `maxAge`. A missing date counts as
    /// expired: data whose age can't be told can't be shown as recent.
    static func isExpired(_ date: Date?, now: Date = Date()) -> Bool {
        guard let date = date else { return true }
        return now.timeIntervalSince(date) > maxAge
    }

    /// Modification date of a cache file, which every store here rewrites
    /// whole on each successful fetch.
    static func modificationDate(of file: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    // MARK: Purge

    /// Whether a top-level Application Support file is one of the offline
    /// caches. Anything else there (Firebase, SDK state, …) is left alone.
    static func isCacheFile(named name: String) -> Bool {
        (name.hasPrefix("stations-") && name.hasSuffix(".json"))
            || (name.hasPrefix(PollutantCache.fileNamePrefix) && name.hasSuffix(".json"))
            || name == "aqi-forecast.json"
            || name == "station-cams-manifest.json"
    }

    /// Deletes every offline cache file last written more than `maxAge` ago:
    /// the station lists, last good pollutants, the area forecast, the cam
    /// manifest and saved cam frames in `directory` (Application Support).
    /// Returns the files removed.
    ///
    /// Each store also ignores an expired file when it reads one, so this is
    /// housekeeping rather than what keeps old data off screen.
    @discardableResult
    static func purge(
        directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        now: Date = Date()
    ) -> [URL] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        func contents(of directory: URL) -> [URL] {
            (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        }
        func isExpiredFile(_ file: URL) -> Bool {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                return false
            }
            return isExpired(values.contentModificationDate, now: now)
        }

        let candidates = contents(of: directory).filter { isCacheFile(named: $0.lastPathComponent) }
            + contents(of: directory.appendingPathComponent(StationCamFrameCache.directoryName, isDirectory: true))

        var removed: [URL] = []
        for file in candidates where isExpiredFile(file) {
            if (try? fileManager.removeItem(at: file)) != nil {
                removed.append(file)
            }
        }
        return removed
    }

    /// `purge` off the main thread, plus the app group's cached readings.
    /// Called at launch.
    static func purgeInBackground() {
        DispatchQueue.global(qos: .utility).async {
            let removed = purge()
            if !removed.isEmpty {
                print("OfflineCacheRetention purged", removed.map(\.lastPathComponent))
            }
        }
        WatchStore.purgeExpiredReadings()
    }
}
