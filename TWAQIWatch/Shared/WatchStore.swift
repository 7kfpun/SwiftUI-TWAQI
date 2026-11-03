//
//  WatchStore.swift
//  TWAQIWatch
//
//  Created by kf on 20/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// State the watch app shares with its complications.
///
/// Lives in the app group rather than `.standard`: the widget extension is a
/// separate process and can't read the app's own defaults.
enum WatchStore {
    static let appGroup = "group.com.kfpun.twaqi"

    /// The app is scoped to one supported country, like the iOS app.
    static let countryCode = "twn"

    private enum Keys {
        static let pinnedStationId = "pinnedStationId"
        static let latestReading = "latestReading"
        static let homeReading = "homeReading"
        static let homeIsLocated = "homeIsLocated"
        static let isProUnlocked = "isProUnlocked"
        static let favouriteStationIds = "favouriteStationIds"
        static let favouriteReadings = "favouriteReadings"
        static let relevanceHistory = "relevanceHistory"
        static let alertThresholds = "alertThresholds"
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// A station the reader picked by hand. `nil` means home: the closest
    /// station, or the 中正 default without a location.
    static var pinnedStationId: Int? {
        get { defaults.object(forKey: Keys.pinnedStationId) as? Int }
        set { defaults.set(newValue, forKey: Keys.pinnedStationId) }
    }

    /// Last reading fetched, so the app and complications have something to
    /// show before — or without — a network round trip. Its station is also
    /// the one the complications follow, since they can't locate the reader.
    static var latestReading: WatchReading? {
        get { reading(forKey: Keys.latestReading) }
        set { setReading(newValue, forKey: Keys.latestReading) }
    }

    /// The station home last resolved to, so the picker can name it even while
    /// another station is pinned.
    static var homeReading: WatchReading? {
        get { reading(forKey: Keys.homeReading) }
        set { setReading(newValue, forKey: Keys.homeReading) }
    }

    /// Whether `homeReading` came from the reader's location, not the 中正
    /// default: location permission was given. The watch Smart Stack's "near
    /// home" hint needs it and never asks for permission itself.
    static var homeIsLocated: Bool {
        get { defaults.bool(forKey: Keys.homeIsLocated) }
        set { defaults.set(newValue, forKey: Keys.homeIsLocated) }
    }

    /// Readings older than this are not shown, and are removed by
    /// `purgeExpiredReadings`: past a week a cached reading says more about
    /// when the device was last online than about the air. The same ceiling as
    /// the phone app's `OfflineCacheRetention.maxAge`.
    static let maxReadingAge: TimeInterval = 7 * 24 * 60 * 60

    /// True when `reading` was published more than `maxReadingAge` ago. A
    /// publish time that doesn't parse (the gallery placeholders) is kept.
    static func isExpired(_ reading: WatchReading, now: Date = Date()) -> Bool {
        guard let published = publishedDate(of: reading) else { return false }
        return now.timeIntervalSince(published) > maxReadingAge
    }

    /// When `reading` was published, or nil when its publish time doesn't
    /// parse (the gallery placeholders).
    static func publishedDate(of reading: WatchReading) -> Date? {
        publishTimeFormatter.date(from: reading.publishTime)
    }

    /// Deletes cached readings older than `maxReadingAge`. Reads already skip
    /// them; this frees the space and keeps the app group tidy.
    static func purgeExpiredReadings(now: Date = Date()) {
        for key in [Keys.latestReading, Keys.homeReading] {
            if let stored = storedReading(forKey: key), isExpired(stored, now: now) {
                defaults.removeObject(forKey: key)
            }
        }
        let favourites = storedFavouriteReadings
        let kept = favourites.filter { !isExpired($0, now: now) }
        if kept.count != favourites.count {
            favouriteReadings = kept
        }
        let history = storedRelevanceHistory
        let keptHistory = history.filter { !isExpired($0, now: now) }
        if keptHistory.count != history.count {
            relevanceHistory = keptHistory
        }
    }

    /// `publish_time` is Taiwan local time with no zone.
    private static let publishTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        return formatter
    }()

    /// Mirror of the iOS app's saved favourites, in the reader's order, for the
    /// medium and large Home Screen widgets. `SettingsStore` on the phone is
    /// the source of truth; only `WidgetBridge` writes this.
    static var favouriteStationIds: [Int] {
        get { defaults.array(forKey: Keys.favouriteStationIds) as? [Int] ?? [] }
        set { defaults.set(newValue, forKey: Keys.favouriteStationIds) }
    }

    /// Last reading fetched for each favourite, so the widget lists them
    /// offline. Unordered; look rows up by `stationId`. Readings older than
    /// `maxReadingAge` are left out.
    static var favouriteReadings: [WatchReading] {
        get { storedFavouriteReadings.filter { !isExpired($0) } }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Keys.favouriteReadings) }
    }

    private static var storedFavouriteReadings: [WatchReading] {
        defaults.data(forKey: Keys.favouriteReadings)
            .flatMap { try? JSONDecoder().decode([WatchReading].self, from: $0) } ?? []
    }

    /// Merges freshly fetched favourite readings into `favouriteReadings`,
    /// replacing older readings of the same stations.
    static func cacheFavouriteReadings(_ fresh: [WatchReading]) {
        guard !fresh.isEmpty else { return }
        let freshIds = Set(fresh.map(\.stationId))
        favouriteReadings = favouriteReadings.filter { !freshIds.contains($0.stationId) } + fresh
    }

    /// The widget's own record of each station's last two publishes, so its
    /// relevance can tell a worsening reading (`WidgetRelevance.recording`).
    /// Written by the widget extensions only. Readings older than
    /// `maxReadingAge` are left out.
    static var relevanceHistory: [WatchReading] {
        get { storedRelevanceHistory.filter { !isExpired($0) } }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Keys.relevanceHistory) }
    }

    private static var storedRelevanceHistory: [WatchReading] {
        defaults.data(forKey: Keys.relevanceHistory)
            .flatMap { try? JSONDecoder().decode([WatchReading].self, from: $0) } ?? []
    }

    /// Adds `reading` to `relevanceHistory` and returns the station's reading
    /// from the publish before it, if one is held.
    @discardableResult
    static func recordForRelevance(_ reading: WatchReading) -> WatchReading? {
        let history = WidgetRelevance.recording(reading, in: relevanceHistory)
        relevanceHistory = history
        return WidgetRelevance.previous(of: reading, in: history)
    }

    /// Mirror of the phone's "above" alert thresholds (AQI) by station id, for
    /// the Home Screen widget's relevance. `DirectusPushMirror` on the phone is
    /// the source of truth; only `WidgetBridge` writes this. Empty on the
    /// watch, which has no copy of the phone's alerts.
    static var alertThresholds: [Int: Int] {
        get {
            let stored = defaults.dictionary(forKey: Keys.alertThresholds) as? [String: Int] ?? [:]
            return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in Int(key).map { ($0, value) } })
        }
        set {
            defaults.set(Dictionary(uniqueKeysWithValues: newValue.map { (String($0.key), $0.value) }), forKey: Keys.alertThresholds)
        }
    }

    /// Cache of `WatchPro.refresh()` on the watch, and of `SettingsStore.refreshPro()`
    /// (via `WidgetBridge`) on the phone; StoreKit is the source of truth.
    static var isProUnlocked: Bool {
        get { defaults.bool(forKey: Keys.isProUnlocked) }
        set { defaults.set(newValue, forKey: Keys.isProUnlocked) }
    }

    /// The cached reading, unless it is older than `maxReadingAge`.
    private static func reading(forKey key: String) -> WatchReading? {
        storedReading(forKey: key).flatMap { isExpired($0) ? nil : $0 }
    }

    private static func storedReading(forKey key: String) -> WatchReading? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(WatchReading.self, from: $0) }
    }

    private static func setReading(_ reading: WatchReading?, forKey key: String) {
        defaults.set(reading.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}
