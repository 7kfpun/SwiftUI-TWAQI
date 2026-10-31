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
        static let isProUnlocked = "isProUnlocked"
        static let favouriteStationIds = "favouriteStationIds"
        static let favouriteReadings = "favouriteReadings"
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

    /// Readings older than this are not shown, and are removed by
    /// `purgeExpiredReadings`: past a week a cached reading says more about
    /// when the device was last online than about the air. The same ceiling as
    /// the phone app's `OfflineCacheRetention.maxAge`.
    static let maxReadingAge: TimeInterval = 7 * 24 * 60 * 60

    /// True when `reading` was published more than `maxReadingAge` ago. A
    /// publish time that doesn't parse (the gallery placeholders) is kept.
    static func isExpired(_ reading: WatchReading, now: Date = Date()) -> Bool {
        guard let published = publishTimeFormatter.date(from: reading.publishTime) else { return false }
        return now.timeIntervalSince(published) > maxReadingAge
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
