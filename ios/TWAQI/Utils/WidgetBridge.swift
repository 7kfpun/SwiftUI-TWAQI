//
//  WidgetBridge.swift
//  TWAQI
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
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
/// - `alertThresholds` — each station's "above" alert threshold, from
///   `DirectusPushMirror`, which stays the source of truth; the widget's
///   relevance peaks there (FOX-75).
/// - `appLanguage` — mirror of `SettingsStore.appLanguage` (Help → Language),
///   so the widget shows the language the app does.
///
/// The Control Center control reads the same keys, so it is reloaded with
/// the widget; Siri's station phrases list the favourites, so they are
/// refreshed when those change (FOX-74).
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
        reloadControls()
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
            reloadControls()
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
        reloadControls()
        updateShortcutStations()
        WatchEventRelay.shared.sendFavourites(ids)
    }

    /// Refreshes the cached reading of any favourite station in `pollutants`,
    /// so the widget lists it offline. Doesn't reload timelines: the widget
    /// fetches favourites itself and only falls back to this cache.
    static func cacheFavourites(from pollutants: Pollutants) {
        let ids = Set(WatchStore.favouriteStationIds)
        let named = Set(WatchStore.favouriteReadings.map(\.stationId))
        let fresh = pollutants.filter { ids.contains($0.stationId) }
        WatchStore.cacheFavouriteReadings(fresh.map(WatchReading.init))
        // A favourite seen for the first time now has a name Siri can match.
        if fresh.contains(where: { !named.contains($0.stationId) }) {
            updateShortcutStations()
        }
    }

    /// Mirrors the "above" alert thresholds into the app group, so a widget
    /// leading with a station over its threshold tops a StandBy or Smart
    /// Rotate stack. Called at launch and whenever the app leaves the
    /// foreground: the widget isn't on screen while the app is, and a slider
    /// drag would otherwise reload it at every step. Only reads the alerts;
    /// never writes them.
    static func publishAlertThresholds() {
        publish(alertThresholds: DirectusPushMirror.alertedStations().compactMapValues(\.above))
    }

    static func publish(alertThresholds: [Int: Int]) {
        guard alertThresholds != WatchStore.alertThresholds else { return }
        WatchStore.alertThresholds = alertThresholds
        WidgetCenter.shared.reloadTimelines(ofKind: homeWidgetKind)
    }

    /// Mirrors the Help language choice into the app group. Called on every
    /// change and once at launch, for a choice made by an older build.
    static func publish(appLanguage: AppLanguage) {
        guard AppLanguage.mirror(appLanguage, to: AppLanguage.shared) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: homeWidgetKind)
        reloadControls()
        updateShortcutStations()
    }

    /// The large widget lists favourites only with Pro. The phone's app group
    /// is separate from the watch's, so the phone mirrors its own answer here.
    static func publish(isPro: Bool) {
        guard isPro != WatchStore.isProUnlocked else { return }
        WatchStore.isProUnlocked = isPro
        WidgetCenter.shared.reloadTimelines(ofKind: homeWidgetKind)
    }

    /// Mirrors whether the app may use location into the app group, for the
    /// control's "Nearest" (FOX-74). Called at launch, whenever the app
    /// becomes active (after the system prompt, or a change in Settings)
    /// and when it leaves the foreground. Never asks for permission.
    static func publishLocationPermission() {
        let allowed: Bool
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: allowed = true
        default: allowed = false
        }
        guard allowed != WatchStore.appLocationAllowed else { return }
        WatchStore.appLocationAllowed = allowed
        reloadControls()
    }

    /// The Control Center control shows the same reading as the widget.
    private static func reloadControls() {
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
    }

    /// Siri's "air at <station>" phrases list "Nearest" and the favourites
    /// by name. Also called once at launch.
    static func updateShortcutStations() {
        if #available(iOS 16.0, *) {
            TWAQIShortcuts.favouritesChanged()
        }
    }
}
