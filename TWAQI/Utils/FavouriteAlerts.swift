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
/// OneSignal's tags stay the source of truth, always written first, with the
/// Directus copy only after OneSignal has taken the write. The mirror's
/// record of the last alerts sent stands in while OneSignal can't be read
/// (offline, not registered yet). The one store of its own is the clears
/// OneSignal hasn't taken yet, so leaving Favourites offline still turns the
/// station's alerts off later.
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
    /// screen locks its switches once other stations reach it.
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

    // MARK: - Leaving Favourites turns alerts off

    /// Which tag prefixes to clear when a station leaves Favourites: none
    /// when its alerts are known to be off, the one OneSignal has it under
    /// when that is known, and otherwise every candidate. With no record on
    /// this device and OneSignal not read (offline, a reinstall, alerts set
    /// before the Directus copy), the state is unknown: clearing a tag that
    /// was never set is harmless, leaving an alert on is not.
    static func tagCodesToClear(alertsOn: Bool?, knownTagCode: String?, candidates: [String]) -> [String] {
        if alertsOn == false {
            return []
        }
        return knownTagCode.map { [$0] } ?? candidates
    }

    /// Turns both of a station's alerts off as it leaves Favourites.
    ///
    /// OneSignal first. Only once OneSignal has taken the write does the
    /// Directus copy follow and the station read as off elsewhere; a
    /// Directus failure never touches OneSignal. Until OneSignal takes it the
    /// clear is kept on this device and tried again (`retryPendingClears`), so
    /// a station removed offline still loses its alerts. Calls back on the
    /// main thread with whether OneSignal took it.
    static func clear(
        stationId: Int,
        tagCodes: [String],
        services: Services = .live,
        completion: ((Bool) -> Void)? = nil
    ) {
        let codes = Array(Set(tagCodes)).sorted()
        guard !codes.isEmpty else {
            DispatchQueue.main.async { completion?(true) }
            return
        }
        var pending = pendingClears(defaults: services.defaults)
        pending[stationId] = codes
        savePendingClears(pending, defaults: services.defaults)

        TrackingManager.logEvent(eventName: "station_alerts_cleared_by_unfavourite", parameters: [
            "stationId": stationId,
        ])
        sendClear(stationId: stationId, tagCodes: codes, services: services, completion: completion)
    }

    /// Clears that OneSignal hasn't taken yet, tried again. A station that is
    /// a favourite again is dropped: its alerts are its own once more.
    /// One still on the wire is left to answer, not sent a second time.
    /// Main thread.
    static func retryPendingClears(
        isFavourite: (Int) -> Bool = { SettingsStore().savedFavouriteStations.contains($0) },
        services: Services = .live
    ) {
        for (stationId, codes) in pendingClears(defaults: services.defaults) {
            if isFavourite(stationId) {
                cancelPendingClear(stationId: stationId, defaults: services.defaults)
            } else if !isClearInFlight(stationId: stationId) {
                sendClear(stationId: stationId, tagCodes: codes, services: services, completion: nil)
            }
        }
    }

    /// Station id → tag prefixes still to clear in OneSignal.
    static func pendingClears(defaults: UserDefaults = .standard) -> [Int: [String]] {
        let stored = defaults.data(forKey: pendingClearsKey)
            .flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, codes in Int(key).map { ($0, codes) } })
    }

    /// The station is a favourite again, so a clear still waiting must not
    /// turn off the alerts it is about to get.
    static func cancelPendingClear(stationId: Int, defaults: UserDefaults = .standard) {
        var pending = pendingClears(defaults: defaults)
        guard pending.removeValue(forKey: stationId) != nil else { return }
        savePendingClears(pending, defaults: defaults)
    }

    private static let pendingClearsKey = "favouriteAlertsPendingClears"

    private static func savePendingClears(_ pending: [Int: [String]], defaults: UserDefaults) {
        let stored = Dictionary(uniqueKeysWithValues: pending.map { (String($0.key), $0.value) })
        defaults.set(try? JSONEncoder().encode(stored), forKey: pendingClearsKey)
    }

    /// Main thread. Anything for the station that would write OneSignal
    /// waits until this has answered (`afterClearsSettle`), so OneSignal
    /// takes this clear before it and the Directus copy follows in the same
    /// order.
    private static func sendClear(
        stationId: Int,
        tagCodes: [String],
        services: Services,
        completion: ((Bool) -> Void)?
    ) {
        var tags: [String: String] = [:]
        for code in tagCodes {
            tags.merge(off(tagCode: code).getDisabledTags()) { _, new in new }
        }
        clearsInFlight[stationId, default: 0] += 1
        services.sendTags(tags) { result in
            DispatchQueue.main.async {
                defer { clearSettled(stationId: stationId) }
                guard case .success = result else {
                    completion?(false)
                    return
                }
                // OneSignal has them off now, even when the station was
                // favourited again meanwhile: what that does waits for this
                // and writes, and copies, after it.
                var pending = pendingClears(defaults: services.defaults)
                if pending[stationId] == tagCodes {
                    pending[stationId] = nil
                    savePendingClears(pending, defaults: services.defaults)
                }
                services.mirror(stationId, nil, .off, true)
                // A switch moved on the station screen meanwhile is about to
                // be written: the screen keeps showing it rather than "off".
                let switchWriteWaiting = afterClears[stationId]?.contains { $0.isSwitchWrite } ?? false
                if !switchWriteWaiting {
                    post(stationId: stationId, isOn: false)
                }
                completion?(true)
            }
        }
    }

    // MARK: - Clears still on the wire

    /// Clears handed to OneSignal that haven't answered yet, per station.
    /// OneSignal can take a clear after a write sent later, or a read can
    /// still see the alerts the clear is about to remove, so writes for the
    /// station wait for these. Main thread only.
    private static var clearsInFlight: [Int: Int] = [:]

    private struct AfterClear {
        let isSwitchWrite: Bool
        let run: () -> Void
    }

    private static var afterClears: [Int: [AfterClear]] = [:]

    /// A clear for the station is on the wire. Main thread.
    static func isClearInFlight(stationId: Int) -> Bool {
        clearsInFlight[stationId, default: 0] > 0
    }

    /// Runs `work` on the main thread once no clear for the station is on
    /// the wire — at once when none is — in the order asked.
    private static func afterClearsSettle(stationId: Int, isSwitchWrite: Bool = false, _ work: @escaping () -> Void) {
        onMain {
            guard isClearInFlight(stationId: stationId) else { return work() }
            afterClears[stationId, default: []].append(AfterClear(isSwitchWrite: isSwitchWrite, run: work))
        }
    }

    private static func clearSettled(stationId: Int) {
        let left = clearsInFlight[stationId, default: 1] - 1
        guard left <= 0 else {
            clearsInFlight[stationId] = left
            return
        }
        clearsInFlight[stationId] = nil
        let waiting = afterClears.removeValue(forKey: stationId) ?? []
        waiting.forEach { $0.run() }
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private static func off(tagCode: String) -> OneSignalStationSetting {
        OneSignalStationSetting(
            stationName: tagCode,
            isPollutionNotificationEnabled: false,
            isCleanlinessNotificationEnabled: false
        )
    }

    // MARK: - Help's "cancel all"

    /// Turns every station's alerts off: OneSignal first, the Directus copy
    /// only once OneSignal has taken every write. If OneSignal can't be read
    /// or written, Directus is left as it is, so the copy never says off
    /// while OneSignal still sends. The same write takes the clears still
    /// waiting here and any station tag too garbled to read, so neither is
    /// left on. Calls back on the main thread with whether it worked.
    static func cancelAll(services: Services = .live, completion: @escaping (Bool) -> Void) {
        services.readSettings { result in
            guard case .success(let settings) = result else {
                return DispatchQueue.main.async { completion(false) }
            }

            var tags: [String: String] = [:]
            for setting in settings.stationSettings.values {
                tags.merge(setting.getDisabledTags()) { _, new in new }
            }
            let pending = pendingClears(defaults: services.defaults)
            let codes = pending.values.flatMap { $0 } + settings.unreadableStationTagCodes
            for code in codes {
                tags.merge(off(tagCode: code).getDisabledTags()) { _, new in new }
            }

            let finish = {
                DispatchQueue.main.async {
                    services.mirrorCancelAll()
                    // Only the clears this write took: one saved meanwhile
                    // is still to do.
                    var left = pendingClears(defaults: services.defaults)
                    for (stationId, codes) in pending where left[stationId] == codes {
                        left[stationId] = nil
                    }
                    savePendingClears(left, defaults: services.defaults)
                    completion(true)
                }
            }
            guard !tags.isEmpty else { return finish() }

            services.sendTags(tags) { result in
                guard case .success = result else {
                    return DispatchQueue.main.async { completion(false) }
                }
                finish()
            }
        }
    }

    // MARK: - The station screen's switches

    /// Writes a station's alerts as set on its screen: OneSignal first, then
    /// the Directus copy — debounced, since a slider sends a value per step —
    /// only once OneSignal has taken it, and only while `isCurrent` (a later
    /// change brings its own copy). Sent once any clear of the station on
    /// the wire has answered, so that clear can't land after it. Calls back
    /// on the main thread with whether OneSignal took it.
    static func write(
        _ setting: OneSignalStationSetting,
        stationId: Int,
        siteId: String?,
        isCurrent: @escaping () -> Bool,
        services: Services = .live,
        completion: @escaping (Bool) -> Void
    ) {
        afterClearsSettle(stationId: stationId, isSwitchWrite: true) {
            services.sendTags(setting.getTags()) { result in
                DispatchQueue.main.async {
                    guard case .success = result else { return completion(false) }
                    if isCurrent() {
                        services.mirror(stationId, siteId, StationAlerts(setting), false)
                    }
                    completion(true)
                }
            }
        }
    }

    /// Stations with an alert on.
    static func alertedStationCount(_ settings: OneSignalSettings) -> Int {
        settings.stationSettings.values.filter { !StationAlerts($0).isOff }.count
    }

    /// `maxAlertedStations` *other* stations already have alerts, so this
    /// one's switches that are off stay locked. A station's own alerts don't
    /// count: with its "above" alert on, its "below" one adds no station.
    static func isAtCap(_ settings: OneSignalSettings, excluding tagCode: String) -> Bool {
        let others = settings.stationSettings.filter { $0.key != tagCode && !StationAlerts($0.value).isOff }
        return others.count >= maxAlertedStations
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
        if isAtCap(settings, excluding: tagCode) {
            return .capReached
        }
        return .enabled(defaultAlerts(tagCode: tagCode))
    }

    /// What the writes here talk to; swapped out in tests.
    struct Services {
        /// Calls back true when the user has turned notifications off for the app.
        var notificationsDenied: (@escaping (Bool) -> Void) -> Void
        var readSettings: (@escaping (Result<OneSignalSettings, OneSignalError>) -> Void) -> Void
        var sendTags: ([String: String], @escaping (Result<Bool, OneSignalError>) -> Void) -> Void
        /// The Directus copy of a station, after OneSignal has taken the
        /// write. `settled` false waits for a slider to stop.
        var mirror: (_ stationId: Int, _ siteId: String?, _ alerts: StationAlerts, _ settled: Bool) -> Void
        /// The Directus copy of "cancel all", after OneSignal has taken it.
        var mirrorCancelAll: () -> Void
        /// Where clears OneSignal hasn't taken yet are kept.
        var defaults: UserDefaults

        static let live = Services(
            notificationsDenied: { completion in
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    completion(settings.authorizationStatus == .denied)
                }
            },
            readSettings: OneSignalManager.getOneSignalSettings,
            sendTags: { tags, completion in OneSignalManager.sendTags(tags: tags, completionHandler: completion) },
            mirror: { stationId, siteId, alerts, settled in
                Task { @MainActor in
                    DirectusPushMirror.shared.stationChanged(stationId: stationId, siteId: siteId, alerts: alerts, settled: settled)
                }
            },
            mirrorCancelAll: {
                Task { @MainActor in
                    DirectusPushMirror.shared.cancelAll()
                }
            },
            defaults: .standard
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

        // A favourite again: a clear from when it last left must not undo
        // what happens next. One already on the wire can't be called back,
        // so this waits for it to answer: reading before then could still
        // see the alerts it removes, and writing before then could be
        // undone by it.
        cancelPendingClear(stationId: stationId, defaults: services.defaults)

        afterClearsSettle(stationId: stationId) {
            enableAfterClears(
                stationId: stationId,
                tagCode: tagCode,
                siteId: siteId,
                isStillFavourite: isStillFavourite,
                services: services,
                finish: finish
            )
        }
    }

    private static func enableAfterClears(
        stationId: Int,
        tagCode: String,
        siteId: String?,
        isStillFavourite: @escaping () -> Bool,
        services: Services,
        finish: @escaping (NewFavouriteOutcome) -> Void
    ) {
        services.notificationsDenied { denied in
            guard !denied else { return finish(.notificationsDenied) }

            services.readSettings { result in
                guard case .success(let settings) = result else { return finish(.notChanged) }

                let decision = newFavouriteDecision(settings: settings, tagCode: tagCode)
                guard case .enabled(let setting) = decision else { return finish(decision) }

                // Unfavourited and favourited again during the read: wait
                // for that clear too.
                afterClearsSettle(stationId: stationId) {
                    guard isStillFavourite() else { return finish(.notChanged) }

                    services.sendTags(setting.getTags()) { result in
                        guard case .success = result else { return finish(.notChanged) }

                        DispatchQueue.main.async {
                            services.mirror(stationId, siteId, StationAlerts(setting), true)
                            let alerted = alertedStationCount(settings) + 1
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
