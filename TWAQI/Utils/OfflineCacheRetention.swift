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
}
