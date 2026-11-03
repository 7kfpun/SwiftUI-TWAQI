//
//  FavouriteAlerts.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import UserNotifications

/// Keeps a station's alerts and its place in Favourites together: a station
/// with an alert on is always a favourite, and leaving Favourites turns its
/// alerts off.
///
/// Alerts live in `DirectusPushMirror`: written on the device at once, so a
/// change here always takes, and copied to Directus — where the FCM sender
/// reads them — in the background, retried until it lands. Every write goes
/// through `Services`, so tests can swap it out. Call from the main thread.
enum FavouriteAlerts {
    /// Posted on the main thread when a station's alerts are switched on or
    /// off: changed on the station screen, cleared from Favourites, switched
    /// on by favouriting, or restored after a reinstall. `userInfo` holds
    /// `stationIdKey` and `isOnKey`.
    static let changed = Notification.Name("FavouriteAlerts.changed")
    static let stationIdKey = "stationId"
    static let isOnKey = "isOn"
    /// Optional: the alerts just switched on elsewhere (a new favourite, a
    /// restore), for a station screen already showing the switches to take
    /// as they are.
    static let settingKey = "setting"

    // Any number of stations can have alerts (FOX-41): the two-station cap
    // belonged to the OneSignal setup and went with it.

    static func post(stationId: Int, isOn: Bool, setting: StationAlertSetting? = nil) {
        var userInfo: [String: Any] = [
            stationIdKey: stationId,
            isOnKey: isOn,
        ]
        userInfo[settingKey] = setting
        NotificationCenter.default.post(name: changed, object: nil, userInfo: userInfo)
    }

    /// The alerts a `changed` notification carries, when it carries them.
    static func setting(in notification: Notification) -> StationAlertSetting? {
        notification.userInfo?[settingKey] as? StationAlertSetting
    }

    /// Reads a `changed` notification for one station.
    static func isOn(in notification: Notification, stationId: Int) -> Bool? {
        guard notification.userInfo?[stationIdKey] as? Int == stationId else { return nil }
        return notification.userInfo?[isOnKey] as? Bool
    }

    /// Whether the station has an alert on.
    static func isOn(stationId: Int, services: Services = .live) -> Bool {
        services.alertedStations()[stationId] != nil
    }

    /// Stations with an alert on.
    static func alertedStationIds(services: Services = .live) -> Set<Int> {
        Set(services.alertedStations().keys)
    }

    // MARK: - The station screen's switches

    /// Writes a station's alerts as set on its screen. The Directus copy
    /// waits for a slider to stop.
    static func write(_ setting: StationAlertSetting, stationId: Int, siteId: String?, services: Services = .live) {
        services.write(stationId, siteId, StationAlerts(setting), false)
    }

    // MARK: - Leaving Favourites turns alerts off

    /// Turns both of a station's alerts off as it leaves Favourites. Nothing
    /// to do when they are off already.
    static func clear(stationId: Int, services: Services = .live) {
        guard isOn(stationId: stationId, services: services) else { return }
        services.write(stationId, nil, .off, true)
        TrackingManager.logEvent(eventName: "station_alerts_cleared_by_unfavourite", parameters: [
            "stationId": stationId,
        ])
        post(stationId: stationId, isOn: false)
    }

    // MARK: - Help's "cancel all"

    /// Turns every station's alerts off, including any in Directus for
    /// stations this install never opened.
    static func cancelAll(services: Services = .live) {
        let alerted = alertedStationIds(services: services)
        services.cancelAll()
        for stationId in alerted.sorted() {
            post(stationId: stationId, isOn: false)
        }
    }

    // MARK: - A new favourite switches its alerts on (FOX-31)

    /// What favouriting a station does to its alerts.
    enum NewFavouriteOutcome: Equatable {
        /// Switched on with `defaultAlerts`.
        case enabled(StationAlertSetting)
        /// Already on: left as they are.
        case alreadyOn
        /// Notifications are turned off for the app in Settings.
        case notificationsDenied
        /// The station stopped being a favourite before it was written.
        case notChanged
    }

    /// What a station gets when favouriting switches its alerts on: the
    /// "above" alert at the station screen's own starting threshold (AQI
    /// 120, unhealthy for sensitive groups), as if switched on there. The
    /// "below" alert stays off — it is the clean-air nudge, not a warning.
    static let defaultAlerts = StationAlertSetting(
        isPollutionNotificationEnabled: true,
        isCleanlinessNotificationEnabled: false
    )

    /// The decision, from the stations with alerts on.
    static func newFavouriteDecision(alertedStationIds: Set<Int>, stationId: Int) -> NewFavouriteOutcome {
        alertedStationIds.contains(stationId) ? .alreadyOn : .enabled(defaultAlerts)
    }

    /// What the writes here talk to; swapped out in tests.
    struct Services {
        /// Calls back true when the user has turned notifications off for the app.
        var notificationsDenied: (@escaping (Bool) -> Void) -> Void
        /// Stations with an alert on, and their alerts.
        var alertedStations: () -> [Int: StationAlerts]
        /// Saves a station's alerts. `settled` false waits for a slider to
        /// stop before the Directus copy.
        var write: (_ stationId: Int, _ siteId: String?, _ alerts: StationAlerts, _ settled: Bool) -> Void
        /// Help's "cancel all".
        var cancelAll: () -> Void

        static let live = Services(
            notificationsDenied: { completion in
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    completion(settings.authorizationStatus == .denied)
                }
            },
            alertedStations: { DirectusPushMirror.alertedStations() },
            write: { stationId, siteId, alerts, settled in
                MainActor.assumeIsolated {
                    DirectusPushMirror.shared.stationChanged(stationId: stationId, siteId: siteId, alerts: alerts, settled: settled)
                }
            },
            cancelAll: {
                MainActor.assumeIsolated {
                    DirectusPushMirror.shared.cancelAll()
                }
            }
        )
    }

    /// Switches a just-favourited station's alerts on, unless they are on
    /// already or notifications are off — the favourite stands either way; this
    /// only adds to it. `isStillFavourite` is asked just before writing, so a
    /// station unfavourited meanwhile is left alone. Do-not-disturb is not
    /// touched. Calls back on the main thread.
    static func enableForNewFavourite(
        stationId: Int,
        siteId: String?,
        isStillFavourite: @escaping () -> Bool,
        services: Services = .live,
        completion: @escaping (NewFavouriteOutcome) -> Void
    ) {
        func finish(_ outcome: NewFavouriteOutcome) {
            log(outcome, stationId: stationId)
            completion(outcome)
        }

        services.notificationsDenied { denied in
            DispatchQueue.main.async {
                guard !denied else { return finish(.notificationsDenied) }
                guard isStillFavourite() else { return finish(.notChanged) }

                let alerted = alertedStationIds(services: services)
                let decision = newFavouriteDecision(alertedStationIds: alerted, stationId: stationId)
                guard case .enabled(let setting) = decision else { return finish(decision) }

                services.write(stationId, siteId, StationAlerts(setting), true)
                post(stationId: stationId, isOn: true, setting: setting)
                finish(decision)
            }
        }
    }

    private static func log(_ outcome: NewFavouriteOutcome, stationId: Int) {
        let name: String
        switch outcome {
        case .enabled: name = "enabled"
        case .alreadyOn: name = "already_on"
        case .notificationsDenied: name = "notifications_denied"
        case .notChanged: name = "not_changed"
        }
        TrackingManager.logEvent(eventName: "station_alerts_on_favourite", parameters: [
            "outcome": name,
            "stationId": stationId,
        ])
    }
}
