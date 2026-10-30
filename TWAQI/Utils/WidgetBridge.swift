//
//  WidgetBridge.swift
//  TWAQI
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import WidgetKit

/// Publishes the phone's current station reading into the app group so Home
/// Screen and Lock Screen widgets (and, via the same keys, Watch complications)
/// can show it offline.
///
/// **Keys (reused from `WatchStore`, not a parallel `WidgetStore`):**
/// - `pinnedStationId` — left alone here; the Watch app owns an explicit pin.
/// - `latestReading` — last reading the phone wants widgets to show (closest,
///   or the pinned station when it matches).
/// - `homeReading` — the closest station the map last resolved.
/// - `favouriteStationIds` — mirror of `SettingsStore.savedFavouriteStations`,
///   which stays the source of truth, for the medium and large widgets.
/// - `favouriteReadings` — last readings seen for those stations.
enum WidgetBridge {
    private static let homeWidgetKind = "TWAQIWidget"

    static func publish(closest pollutant: Pollutant?) {
        guard let pollutant else { return }

        let reading = WatchReading(pollutant)
        WatchStore.homeReading = reading

        if let pinned = WatchStore.pinnedStationId, pinned != pollutant.stationId {
            // A Watch-chosen pin differs from the map's closest station: keep
            // home updated, leave latestReading for the widget timeline fetch.
        } else {
            WatchStore.latestReading = reading
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    /// When pollutants reload, refresh the cached reading for a pinned station
    /// if that station is in the payload.
    static func publish(pollutants: Pollutants, closest: Pollutant?) {
        cacheFavourites(from: pollutants)

        if let pinned = WatchStore.pinnedStationId,
           let match = pollutants.first(where: { $0.stationId == pinned }) {
            WatchStore.latestReading = WatchReading(match)
            if let closest {
                WatchStore.homeReading = WatchReading(closest)
            }
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        publish(closest: closest)
    }

    /// Mirrors the saved favourites into the app group. Called on every write
    /// to `SettingsStore.savedFavouriteStations` and once at launch.
    static func publish(favouriteStationIds ids: [Int]) {
        guard ids != WatchStore.favouriteStationIds else { return }
        WatchStore.favouriteStationIds = ids
        WatchStore.favouriteReadings = WatchStore.favouriteReadings.filter { ids.contains($0.stationId) }
        WidgetCenter.shared.reloadTimelines(ofKind: homeWidgetKind)
    }

    /// Refreshes the cached reading of any favourite station in `pollutants`,
    /// so the widget lists it offline. Doesn't reload timelines: the widget
    /// fetches favourites itself and only falls back to this cache.
    static func cacheFavourites(from pollutants: Pollutants) {
        let ids = Set(WatchStore.favouriteStationIds)
        WatchStore.cacheFavouriteReadings(
            pollutants.filter { ids.contains($0.stationId) }.map(WatchReading.init)
        )
    }

    /// The large widget lists favourites only with Pro. The phone's app group
    /// is separate from the watch's, so the phone mirrors its own answer here.
    static func publish(isPro: Bool) {
        guard isPro != WatchStore.isProUnlocked else { return }
        WatchStore.isProUnlocked = isPro
        WidgetCenter.shared.reloadTimelines(ofKind: homeWidgetKind)
    }
}
