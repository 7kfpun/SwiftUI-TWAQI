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
/// No store of its own. OneSignal's tags stay the source of truth, written
/// the way the station screen writes them, with the Directus copy after; the
/// mirror's record of the last alerts sent stands in while OneSignal can't be
/// read (offline, not registered yet).
enum FavouriteAlerts {
    /// Posted on the main thread when a station's alerts are known to be on
    /// or off: read from OneSignal, changed on the station screen, or cleared
    /// from Favourites. `userInfo` holds `stationIdKey` and `isOnKey`.
    static let changed = Notification.Name("FavouriteAlerts.changed")
    static let stationIdKey = "stationId"
    static let isOnKey = "isOn"
    /// Optional: the alerts just switched on elsewhere (a new favourite), for
    /// a station screen already showing the switches to take as they are.
    static let settingKey = "setting"
    /// Optional, with `settingKey`: stations with an alert on, this one included.
    static let alertedStationCountKey = "alertedStationCount"

    /// OneSignal holds alerts for at most this many stations; the station
    /// screen locks its switches once it is reached.
    static let maxAlertedStations = 2

    /// OneSignal tag prefix for a station: the English name for Taiwan, the
    /// numeric id everywhere else.
    static func tagCode(countryCode: String, name: String, stationId: Int) -> String {
        countryCode == "twn" ? name : "\(stationId)"
    }

    /// Tag prefixes a station may be under when its country isn't known, as
    /// on a current-reading row: Taiwan's English name first, then the id.
    static func candidateTagCodes(name: String, stationId: Int) -> [String] {
        [name, "\(stationId)"].filter { !$0.isEmpty }
    }

    static func post(stationId: Int, isOn: Bool, setting: OneSignalStationSetting? = nil, alertedStationCount: Int? = nil) {
        var userInfo: [String: Any] = [
            stationIdKey: stationId,
            isOnKey: isOn,
        ]
        userInfo[settingKey] = setting
        userInfo[alertedStationCountKey] = alertedStationCount
        NotificationCenter.default.post(name: changed, object: nil, userInfo: userInfo)
    }

    /// The alerts a `changed` notification carries, when it carries them.
    static func setting(in notification: Notification) -> OneSignalStationSetting? {
        notification.userInfo?[settingKey] as? OneSignalStationSetting
    }

    static func alertedStationCount(in notification: Notification) -> Int? {
        notification.userInfo?[alertedStationCountKey] as? Int
    }

    /// Reads a `changed` notification for one station.
    static func isOn(in notification: Notification, stationId: Int) -> Bool? {
        guard notification.userInfo?[stationIdKey] as? Int == stationId else { return nil }
        return notification.userInfo?[isOnKey] as? Bool
    }

    /// Last alerts this device sent for the station, as the Directus mirror
    /// recorded them. Nil when it has no record; true or false otherwise.
    static func locallyKnown(stationId: Int) -> Bool? {
        DirectusPushMirror.knownAlerts(stationId: stationId).map { !$0.isOff }
    }

    /// Which of `stations` have an alert on, by the tag prefix each one is
    /// under in OneSignal. Nil when OneSignal can't be read. Calls back on the
    /// main thread.
    static func fetch(
        stations: [(id: Int, tagCodes: [String])],
        completion: @escaping ([Int: String]?) -> Void
    ) {
        OneSignalManager.getOneSignalSettings { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let settings):
                    var alerted: [Int: String] = [:]
                    for station in stations {
                        let on = station.tagCodes.first { code in
                            settings.stationSettings[code].map { !StationAlerts($0).isOff } ?? false
                        }
                        alerted[station.id] = on
                    }
                    completion(alerted)
                case .failure(let error):
                    print(error.localizedDescription)
                    completion(nil)
                }
            }
        }
    }

    /// Turns both of a station's alerts off: OneSignal first, as the station
    /// screen does, then the Directus copy. `tagCodes` are the prefixes to
    /// clear — the one OneSignal has the station under when known. Call on
    /// the main thread: observers update UI.
    static func clear(stationId: Int, tagCodes: [String]) {
        for code in Set(tagCodes) {
            let off = OneSignalStationSetting(
                stationName: code,
                isPollutionNotificationEnabled: false,
                isCleanlinessNotificationEnabled: false
            )
            OneSignalManager.sendTags(tags: off.getDisabledTags()) { result in
                if case .failure(let error) = result {
                    print(error.localizedDescription)
                }
            }
        }
        Task { @MainActor in
            DirectusPushMirror.shared.stationChanged(stationId: stationId, siteId: nil, alerts: .off, settled: true)
        }
        post(stationId: stationId, isOn: false)

        TrackingManager.logEvent(eventName: "station_alerts_cleared_by_unfavourite", parameters: [
            "stationId": stationId,
        ])
    }

    // MARK: - A new favourite switches its alerts on (FOX-31)

    /// What favouriting a station does to its alerts.
    enum NewFavouriteOutcome: Equatable {
        /// Switched on with `defaultAlerts`.
        case enabled(OneSignalStationSetting)
        /// Already on, from this or another device: left as they are.
        case alreadyOn
        /// `maxAlertedStations` other stations already have alerts.
        case capReached
        /// Notifications are turned off for the app in Settings.
        case notificationsDenied
        /// OneSignal couldn't be read or written (offline, not registered),
        /// or the station stopped being a favourite before it was written.
        case notChanged
    }

    /// What a station gets when favouriting switches its alerts on: the
    /// "above" alert at the station screen's own starting threshold (AQI
    /// 120, unhealthy for sensitive groups), as if switched on there. The
    /// "below" alert stays off — it is the clean-air nudge, not a warning.
    static func defaultAlerts(tagCode: String) -> OneSignalStationSetting {
        OneSignalStationSetting(
            stationName: tagCode,
            isPollutionNotificationEnabled: true,
            isCleanlinessNotificationEnabled: false
        )
    }

    /// The decision, from what OneSignal holds. Never `.enabled` past the cap.
    static func newFavouriteDecision(settings: OneSignalSettings, tagCode: String) -> NewFavouriteOutcome {
        if let existing = settings.stationSettings[tagCode], !StationAlerts(existing).isOff {
            return .alreadyOn
        }
        let alerted = settings.stationSettings.values.filter { !StationAlerts($0).isOff }.count
        if alerted >= maxAlertedStations {
            return .capReached
        }
        return .enabled(defaultAlerts(tagCode: tagCode))
    }

    /// What `enableForNewFavourite` talks to; swapped out in tests.
    struct Services {
        /// Calls back true when the user has turned notifications off for the app.
        var notificationsDenied: (@escaping (Bool) -> Void) -> Void
        var readSettings: (@escaping (Result<OneSignalSettings, OneSignalError>) -> Void) -> Void
        var sendTags: ([String: String], @escaping (Result<Bool, OneSignalError>) -> Void) -> Void
        /// The Directus copy, after OneSignal has taken the write.
        var mirror: (_ stationId: Int, _ siteId: String?, _ alerts: StationAlerts) -> Void

        static let live = Services(
            notificationsDenied: { completion in
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    completion(settings.authorizationStatus == .denied)
                }
            },
            readSettings: OneSignalManager.getOneSignalSettings,
            sendTags: { tags, completion in OneSignalManager.sendTags(tags: tags, completionHandler: completion) },
            mirror: { stationId, siteId, alerts in
                Task { @MainActor in
                    DirectusPushMirror.shared.stationChanged(stationId: stationId, siteId: siteId, alerts: alerts, settled: true)
                }
            }
        )
    }

    /// Switches a just-favourited station's alerts on, unless it is past the
    /// cap, notifications are off, or OneSignal can't be reached — the
    /// favourite stands either way; this only adds to it.
    ///
    /// Written like the station screen writes them: OneSignal first, the
    /// Directus copy only once OneSignal has it, and a Directus failure never
    /// touches OneSignal. `isStillFavourite` is asked just before writing, so
    /// a station unfavourited meanwhile is left alone. Do-not-disturb is
    /// separate tags and is not touched. Calls back on the main thread.
    static func enableForNewFavourite(
        stationId: Int,
        tagCode: String,
        siteId: String?,
        isStillFavourite: @escaping () -> Bool,
        services: Services = .live,
        completion: @escaping (NewFavouriteOutcome) -> Void
    ) {
        func finish(_ outcome: NewFavouriteOutcome) {
            DispatchQueue.main.async {
                log(outcome, stationId: stationId)
                completion(outcome)
            }
        }

        services.notificationsDenied { denied in
            guard !denied else { return finish(.notificationsDenied) }

            services.readSettings { result in
                guard case .success(let settings) = result else { return finish(.notChanged) }

                let decision = newFavouriteDecision(settings: settings, tagCode: tagCode)
                guard case .enabled(let setting) = decision else { return finish(decision) }

                DispatchQueue.main.async {
                    guard isStillFavourite() else { return finish(.notChanged) }

                    services.sendTags(setting.getTags()) { result in
                        guard case .success = result else { return finish(.notChanged) }

                        DispatchQueue.main.async {
                            services.mirror(stationId, siteId, StationAlerts(setting))
                            let alerted = settings.stationSettings.values.filter { !StationAlerts($0).isOff }.count + 1
                            post(stationId: stationId, isOn: true, setting: setting, alertedStationCount: alerted)
                            finish(decision)
                        }
                    }
                }
            }
        }
    }

    private static func log(_ outcome: NewFavouriteOutcome, stationId: Int) {
        let name: String
        switch outcome {
        case .enabled: name = "enabled"
        case .alreadyOn: name = "already_on"
        case .capReached: name = "cap_reached"
        case .notificationsDenied: name = "notifications_denied"
        case .notChanged: name = "not_changed"
        }
        TrackingManager.logEvent(eventName: "station_alerts_on_favourite", parameters: [
            "outcome": name,
            "stationId": stationId,
        ])
    }
}
