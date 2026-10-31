//
//  FavouriteAlerts.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

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

    static func post(stationId: Int, isOn: Bool) {
        NotificationCenter.default.post(name: changed, object: nil, userInfo: [
            stationIdKey: stationId,
            isOnKey: isOn,
        ])
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
}
