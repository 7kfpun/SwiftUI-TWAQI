//
//  DirectusPushMirror.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import OneSignal
import UIKit
import UserNotifications
import Security

/// Keeps the push settings — each station's alerts and the do-not-disturb
/// window — in Directus (`twaqi_push_devices`, `twaqi_push_subscriptions`),
/// where the FCM sender reads them.
///
/// The station page, Favourites and Help write here (through
/// `FavouriteAlerts`); this is the only store for alerts. Changes are kept in
/// `UserDefaults` first, so they take effect on the device at once, and
/// written to Directus after: a failure is logged and retried on the next
/// change, launch, foreground or token change, and never reaches the user.
///
/// The device row is keyed by `PushDeviceIdentity` (a Keychain UUID) and
/// carries the APNs token and the FCM registration token, both handed over
/// by `AppDelegate`. A row is only made once the device has an alert switched
/// on; after that it follows every token change.
@MainActor
final class DirectusPushMirror {
    static let shared = DirectusPushMirror()

    /// A launch refreshes `last_seen_at` at most this often.
    nonisolated static let deviceRefreshInterval: TimeInterval = 6 * 60 * 60
    /// Sliders send a value per step; write once they settle.
    static let debounce: UInt64 = 800_000_000

    private let defaults: UserDefaults
    private let settings = SettingsStore()

    private enum Keys {
        static let deviceId = "directusPushDeviceId"
        static let deviceToken = "directusPushDeviceToken"
        static let fcmToken = "directusPushFcmToken"
        /// `PushDevicePayload.profile` as last written: language and Pro.
        static let profile = "directusPushDeviceProfile"
        static let lastDeviceSyncAt = "directusPushLastDeviceSyncAt"
        /// Station id → alerts as the user set them (or as restored).
        static let wanted = "directusPushWantedAlerts"
        /// Station id → alerts as last written to (or read from) Directus.
        static let synced = "directusPushSyncedAlerts"
        static let siteIds = "directusPushSiteIds"
        /// Help's "cancel all" is still to reach Directus.
        static let archiveAll = "directusPushArchiveAll"
        /// This install has looked for a row an earlier install left.
        static let restored = "directusPushRestored"
    }

    private var apnsToken: String?
    private var fcmToken: String?

    private var isFlushing = false
    private var flushAgain = false
    private var timers: [String: Task<Void, Never>] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Entry points

    /// At launch, and back in the foreground: catches up on anything an
    /// earlier attempt couldn't write, once the tokens arrive.
    func start() {
        flush()
    }

    /// From `didRegisterForRemoteNotificationsWithDeviceToken`.
    func apnsTokenChanged(_ token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        guard hex != apnsToken else { return }
        apnsToken = hex
        flush()
    }

    /// From Messaging's delegate, at launch and whenever FCM rotates it.
    func fcmTokenChanged(_ token: String?) {
        guard let token = token, !token.isEmpty, token != fcmToken else { return }
        fcmToken = token
        flush()
    }

    /// A station's alerts as the user last set them (or as restored),
    /// written to Directus or not. Only reads defaults, so callable from any
    /// thread.
    nonisolated static func alerts(stationId: Int, defaults: UserDefaults = .standard) -> StationAlerts {
        alertedStations(defaults: defaults)[stationId] ?? .off
    }

    /// Stations with at least one alert on, written to Directus or not.
    nonisolated static func alertedStations(defaults: UserDefaults = .standard) -> [Int: StationAlerts] {
        let wanted = defaults.data(forKey: Keys.wanted)
            .flatMap { try? JSONDecoder().decode([String: StationAlerts].self, from: $0) } ?? [:]
        var alerted: [Int: StationAlerts] = [:]
        for (key, alerts) in wanted where !alerts.isOff {
            if let id = Int(key) {
                alerted[id] = alerts
            }
        }
        return alerted
    }

    /// The station row's alerts. `settled` skips the wait, for values read
    /// rather than dragged.
    func stationChanged(stationId: Int, siteId: String?, alerts: StationAlerts, settled: Bool = false) {
        let key = String(stationId)
        if let siteId = siteId {
            var siteIds = load([String: String].self, Keys.siteIds) ?? [:]
            siteIds[key] = siteId
            save(siteIds, Keys.siteIds)
        }
        var wanted = load([String: StationAlerts].self, Keys.wanted) ?? [:]
        guard wanted[key] != alerts || synced[key] != alerts else { return }
        wanted[key] = alerts
        save(wanted, Keys.wanted)

        if settled {
            flush()
        } else {
            later("station-\(key)") { $0.flush() }
        }
    }

    /// Help's do-not-disturb, already saved to `SettingsStore`. Only updates a
    /// device that already has a row.
    func dndChanged() {
        later("dnd") { mirror in
            guard mirror.defaults.object(forKey: Keys.deviceId) != nil else { return }
            // The window is part of the row's profile, so this write is
            // retried until it lands, even across launches.
            mirror.flush()
        }
    }

    /// The user just answered the notification prompt (or changed it): the
    /// row's `notifications_allowed` is written now, not at the next
    /// foreground. Runs again after a sync already in flight, which may have
    /// read the status before the answer.
    func notificationsChanged() {
        flush()
    }

    /// Help's language or Pro changed. Only updates a device that already
    /// has a row; the next write compares `PushDevicePayload.profile`.
    func profileChanged() {
        later("profile") { mirror in
            guard mirror.defaults.object(forKey: Keys.deviceId) != nil else { return }
            mirror.flush()
        }
    }

    /// Help's "cancel all": archives every live alert on this device,
    /// including any for stations this install never opened.
    func cancelAll() {
        timers.values.forEach { $0.cancel() }
        timers = [:]
        let wanted = (load([String: StationAlerts].self, Keys.wanted) ?? [:])
            .merging(synced) { current, _ in current }
            .mapValues { _ in StationAlerts.off }
        save(wanted, Keys.wanted)
        // Kept until done, so a cancel made offline still happens later.
        defaults.set(defaults.object(forKey: Keys.deviceId) != nil, forKey: Keys.archiveAll)
        flush()
    }

    // MARK: - Sync

    private var synced: [String: StationAlerts] {
        load([String: StationAlerts].self, Keys.synced) ?? [:]
    }

    /// Writes whatever differs between the local settings and Directus.
    /// One at a time; a call while one runs makes it go round again.
    private func flush() {
        if isFlushing {
            flushAgain = true
            return
        }
        isFlushing = true
        Task {
            repeat {
                flushAgain = false
                await flushOnce()
            } while flushAgain
            isFlushing = false
        }
    }

    private func flushOnce() async {
        // OneSignal is kept current too, for switching it back on later.
        OneSignalTags.sync(wanted: load([String: StationAlerts].self, Keys.wanted) ?? [:], settings: settings, defaults: defaults)
        guard let config = PushService.Config.current else { return }
        // APNs hasn't registered yet; `apnsTokenChanged` brings us back.
        guard let token = apnsToken else { return }

        if !defaults.bool(forKey: Keys.restored) {
            do {
                try await restore(token: token, config: config)
            } catch {
                // Writing now could overwrite the row being restored from.
                print("Directus push: restore failed: \(error)")
                recover(from: error)
                return
            }
        }

        if defaults.bool(forKey: Keys.archiveAll), defaults.object(forKey: Keys.deviceId) != nil {
            do {
                try await PushService.archiveAll(config: config)
                defaults.set(false, forKey: Keys.archiveAll)
                // Everything is archived now; only changes made since remain.
                let wanted = (load([String: StationAlerts].self, Keys.wanted) ?? [:]).filter { !$0.value.isOff }
                save(wanted, Keys.wanted)
                save([String: StationAlerts](), Keys.synced)
            } catch {
                print("Directus push: cancel all failed: \(error)")
                recover(from: error)
                return
            }
        }

        var wanted = load([String: StationAlerts].self, Keys.wanted) ?? [:]
        var synced = self.synced
        let hasDevice = defaults.object(forKey: Keys.deviceId) != nil

        // An alert that's off and was never written needs nothing.
        for (key, alerts) in wanted where alerts.isOff && (synced[key] ?? .off).isOff {
            wanted[key] = nil
            synced[key] = nil
        }
        save(wanted, Keys.wanted)
        save(synced, Keys.synced)

        let pending = wanted.filter { synced[$0.key] != $0.value }
        guard Self.needsDevice(hasDevice: hasDevice, pending: pending) else { return }

        do {
            _ = try await deviceId(token: token, fcmToken: fcmToken, config: config)
        } catch {
            print("Directus push: device sync failed: \(error)")
            recover(from: error)
            return
        }

        // A new row starts with no alerts: write everything again.
        let refreshed = self.synced
        let siteIds = load([String: String].self, Keys.siteIds) ?? [:]
        for (key, alerts) in wanted where refreshed[key] != alerts {
            do {
                try await PushService.reconcile(stationId: key, siteId: siteIds[key], alerts: alerts, config: config)
                var done = self.synced
                var latest = load([String: StationAlerts].self, Keys.wanted) ?? [:]
                done[key] = alerts
                if alerts.isOff, latest[key] == alerts {
                    done[key] = nil
                    latest[key] = nil
                    save(latest, Keys.wanted)
                }
                save(done, Keys.synced)
            } catch {
                print("Directus push: station \(key) failed: \(error)")
                recover(from: error)
            }
        }
    }

    /// Once per install: finds the row this phone already has — from before a
    /// reinstall (same Keychain id), or one made for its APNs token — and
    /// takes its alerts, and on a fresh install its do-not-disturb window.
    /// Local changes not yet written win over what's restored.
    private func restore(token: String, config: PushService.Config) async throws {
        let isFreshInstall = defaults.object(forKey: Keys.deviceId) == nil

        let restored = try await PushService.restore(deviceToken: token, config: config)
        guard let stored = restored.device else {
            defaults.set(true, forKey: Keys.restored)
            return
        }

        let remote = StationAlerts.byStation(restored.subscriptions)

        if isFreshInstall {
            if let enabled = stored.dndEnabled {
                settings.isDndEnabled = enabled
            }
            if let start = PushService.StoredDevice.time(stored.dndStart) {
                settings.dndStartTime = start
            }
            if let end = PushService.StoredDevice.time(stored.dndEnd) {
                settings.dndEndTime = end
            }
        }

        var wanted = load([String: StationAlerts].self, Keys.wanted) ?? [:]
        var restoredStations: [Int: StationAlerts] = [:]
        for (key, alerts) in remote where wanted[key] == nil {
            wanted[key] = alerts
            restoredStations[Int(key) ?? -1] = alerts
        }
        save(wanted, Keys.wanted)

        // The row is this device's: adopting its id keeps `deviceId(...)`
        // from treating it as new and writing every alert again.
        if defaults.object(forKey: Keys.deviceId) == nil || defaults.integer(forKey: Keys.deviceId) != stored.id {
            defaults.set(stored.id, forKey: Keys.deviceId)
            defaults.removeObject(forKey: Keys.lastDeviceSyncAt)
            save(remote, Keys.synced)
        } else {
            save(synced.merging(remote) { local, _ in local }, Keys.synced)
        }
        defaults.set(true, forKey: Keys.restored)
        announce(restored: restoredStations.filter { $0.key >= 0 })
    }

    /// Restored alerts reach the screens showing them, and their stations
    /// are favourites again: a station with an alert on always is one.
    private func announce(restored: [Int: StationAlerts]) {
        guard !restored.isEmpty else { return }
        var favourites = settings.savedFavouriteStations
        for id in restored.keys.sorted() where !favourites.contains(id) {
            favourites.append(id)
        }
        if favourites != settings.savedFavouriteStations {
            settings.savedFavouriteStations = favourites
        }
        let count = Self.alertedStations(defaults: defaults).count
        for (id, alerts) in restored {
            FavouriteAlerts.post(stationId: id, isOn: true, setting: StationAlertSetting(alerts), alertedStationCount: count)
        }
    }

    /// This device's row, created or refreshed when its tokens, DND,
    /// language, Pro or age call for it.
    private func deviceId(token: String, fcmToken: String?, config: PushService.Config) async throws -> Int {
        let knownId = defaults.object(forKey: Keys.deviceId) != nil ? defaults.integer(forKey: Keys.deviceId) : nil
        guard let stableId = PushDeviceIdentity.id() else { throw PushError.noDeviceId }
        let payload = PushDevicePayload.make(
            deviceId: stableId,
            deviceToken: token,
            fcmToken: fcmToken,
            dndEnabled: settings.isDndEnabled,
            dndStart: settings.dndStartTime,
            dndEnd: settings.dndEndTime,
            isPro: settings.isPro,
            notificationsAllowed: PushDevicePayload.notificationsAllowed(
                await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            ),
            language: settings.appLanguage
        )
        if let knownId = knownId,
           Self.isDeviceCurrent(
               syncedToken: defaults.string(forKey: Keys.deviceToken),
               token: token,
               syncedFcmToken: defaults.string(forKey: Keys.fcmToken),
               fcmToken: fcmToken,
               lastSync: defaults.object(forKey: Keys.lastDeviceSyncAt) as? Date,
               syncedProfile: defaults.string(forKey: Keys.profile),
               profile: payload.profile
           ) {
            return knownId
        }

        let id = try await PushService.upsertDevice(payload, config: config)
        if id != knownId {
            save([String: StationAlerts](), Keys.synced)
        }
        defaults.set(id, forKey: Keys.deviceId)
        defaults.set(token, forKey: Keys.deviceToken)
        if let fcmToken = fcmToken {
            defaults.set(fcmToken, forKey: Keys.fcmToken)
        }
        defaults.set(payload.profile, forKey: Keys.profile)
        defaults.set(Date(), forKey: Keys.lastDeviceSyncAt)
        return id
    }

    // MARK: - Recovering from the push API

    enum Recovery: Equatable {
        /// Another install holds this device id (403): start over with a new
        /// Keychain id and secret, and a new row.
        case newIdentity
        /// The row is gone, retired by a newer registration of this phone's
        /// APNs token (404): register again with the same identity.
        case register
        case none
    }

    nonisolated static func recovery(for error: Error) -> Recovery {
        switch error {
        case PushError.server(statusCode: 403): return .newIdentity
        case PushError.server(statusCode: 404): return .register
        default: return .none
        }
    }

    /// After either recovery the next flush (a change, launch or foreground,
    /// never at once, so a refusing API can't spin it) registers a row and,
    /// seeing a new id, writes every alert again from the device.
    private func recover(from error: Error) {
        let recovery = Self.recovery(for: error)
        guard recovery != .none else { return }
        if recovery == .newIdentity {
            PushDeviceIdentity.reset()
        }
        for key in [Keys.deviceId, Keys.deviceToken, Keys.fcmToken, Keys.profile, Keys.lastDeviceSyncAt] {
            defaults.removeObject(forKey: key)
        }
        save([String: StationAlerts](), Keys.synced)
    }

    // MARK: - Decisions

    /// Whether a flush goes on to the device row: always once one exists (so
    /// a token change alone is written), otherwise only for an alert to turn on.
    nonisolated static func needsDevice(hasDevice: Bool, pending: [String: StationAlerts]) -> Bool {
        hasDevice || pending.values.contains { !$0.isOff }
    }

    /// Whether the row already holds these tokens and was refreshed recently
    /// enough to skip the upsert. A new APNs or FCM token is always written;
    /// a missing FCM token (Messaging hasn't issued one) is not a change. A
    /// new language or Pro status (`profile`) is written too; a row written
    /// before the profile was tracked (no `syncedProfile`) is rewritten once.
    nonisolated static func isDeviceCurrent(
        syncedToken: String?,
        token: String,
        syncedFcmToken: String?,
        fcmToken: String?,
        lastSync: Date?,
        syncedProfile: String? = nil,
        profile: String? = nil,
        now: Date = Date()
    ) -> Bool {
        guard syncedToken == token, let lastSync = lastSync else { return false }
        if let fcmToken = fcmToken, fcmToken != syncedFcmToken { return false }
        if let profile = profile, profile != syncedProfile { return false }
        return now.timeIntervalSince(lastSync) < deviceRefreshInterval
    }

    // MARK: - Helpers

    private func later(_ key: String, _ action: @escaping @MainActor (DirectusPushMirror) -> Void) {
        timers[key]?.cancel()
        timers[key] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounce)
            guard !Task.isCancelled, let self = self else { return }
            self.timers[key] = nil
            action(self)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

/// The device's own id for Directus: a random UUID kept in the Keychain, so it
/// survives reinstalls and APNs token changes, but — `ThisDeviceOnly` — is not
/// carried to a new phone by a backup.
enum PushDeviceIdentity {
    static let service = "com.kfpun.twaqi.push"
    static let account = "directusDeviceId"
    static let secretAccount = "pushDeviceSecret"

    /// The stored id, made on first use. Nil only if the Keychain refuses.
    static func id() -> String? {
        value(account: account) { UUID().uuidString.lowercased() }
    }

    /// This install's secret for the push API (FOX-37 M5): 32 random bytes,
    /// base64url. Made on first use next to the id, with the same "this
    /// device only" access, so a reinstall keeps both and a backup restored
    /// to another phone carries neither. The Worker stores only its hash.
    static func secret() -> String? {
        value(account: secretAccount) {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
            return base64url(Data(bytes))
        }
    }

    /// Forgets the id and secret, so the next use makes new ones: after the
    /// push API refused them (another install holds this id).
    static func reset() {
        for account in [account, secretAccount] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func value(account: String, make: () -> String?) -> String? {
        if let existing = read(account: account) {
            return existing
        }
        guard let made = make() else { return nil }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(made.utf8),
        ]
        switch SecItemAdd(add as CFDictionary, nil) {
        case errSecSuccess:
            return made
        case errSecDuplicateItem:
            return read(account: account)
        case let status:
            print("Push: Keychain refused \(account) (\(status))")
            return nil
        }
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

/// Keeps OneSignal's tags in step with the alerts and do-not-disturb saved
/// here, so OneSignal can be switched back on as a sender with everyone's
/// settings current. FCM is the live sender; OneSignal's own sending is off.
///
/// Write-only and best effort: `DirectusPushMirror.wanted` stays the truth.
/// Station tags are keyed by station id, which the OneSignal tracker matches
/// as well as the English name builds before FOX-13 used; those name tags are
/// removed once per install.
enum OneSignalTags {
    static let pollutionSuffix = "_pollution_therhold"
    static let cleanlinessSuffix = "_cleanliness_therhold"
    static let dndKeys = ["isDndEnabled", "dndStartTime", "dndEndTime", "isDndStartEarlierThanEnd"]

    private enum Keys {
        static let written = "oneSignalWrittenTags"
        static let cleaned = "oneSignalStaleTagsCleaned"
    }

    static var isConfigured: Bool {
        !(getEnv("OneSignalAppId") ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// At launch: OneSignal registers this device (the APNs token it gets is
    /// the same one FCM uses). It never prompts; the app asks for permission.
    static func start(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard isConfigured, let appId = getEnv("OneSignalAppId") else { return }
        OneSignal.initWithLaunchOptions(launchOptions)
        OneSignal.setAppId(appId)
    }

    /// The tags these settings come to: each alert's threshold under
    /// `{stationId}_pollution_therhold` / `_cleanliness_therhold`, and the
    /// do-not-disturb window in minutes, as the OneSignal tracker reads them.
    static func tags(
        wanted: [String: StationAlerts],
        dndEnabled: Bool,
        dndStart: Date,
        dndEnd: Date,
        calendar: Calendar = .current
    ) -> [String: String] {
        var tags: [String: String] = [:]
        for (stationId, alerts) in wanted {
            if let above = alerts.above { tags[stationId + pollutionSuffix] = String(above) }
            if let below = alerts.below { tags[stationId + cleanlinessSuffix] = String(below) }
        }
        if dndEnabled {
            func minutes(_ date: Date) -> Int {
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
            let start = minutes(dndStart)
            let end = minutes(dndEnd)
            tags["isDndEnabled"] = "true"
            tags["dndStartTime"] = String(start)
            tags["dndEndTime"] = String(end)
            // As earlier builds wrote it: true when the window runs past midnight.
            tags["isDndStartEarlierThanEnd"] = String(start > end)
        }
        return tags
    }

    /// What to send: tags that are new or changed, and "" (OneSignal's
    /// delete) for ones written before, or found stale, that are no longer
    /// wanted. Empty when OneSignal already has these settings.
    static func changes(desired: [String: String], written: [String: String], stale: Set<String> = []) -> [String: String] {
        var out = desired.filter { written[$0.key] != $0.value }
        for key in Set(written.keys).union(stale) where desired[key] == nil {
            out[key] = ""
        }
        return out
    }

    /// Whether a tag is a station alert, from this build or an earlier one.
    static func isStationTag(_ key: String) -> Bool {
        key.hasSuffix(pollutionSuffix) || key.hasSuffix(cleanlinessSuffix)
    }

    /// Sends whatever differs from what OneSignal was last told. The first
    /// time on an install it also reads OneSignal's tags and clears station
    /// tags it no longer wants (an earlier build's name-keyed ones).
    @MainActor
    static func sync(wanted: [String: StationAlerts], settings: SettingsStore, defaults: UserDefaults = .standard) {
        guard isConfigured else { return }
        let desired = tags(
            wanted: wanted.filter { !$0.value.isOff },
            dndEnabled: settings.isDndEnabled,
            dndStart: settings.dndStartTime,
            dndEnd: settings.dndEndTime
        )
        let written = defaults.dictionary(forKey: Keys.written) as? [String: String] ?? [:]

        /// `readTags`: OneSignal's own tags were read, so `stale` is complete
        /// and the one-time cleanup is done once this lands. Without them
        /// (not registered yet, offline) the cleanup stays pending.
        func send(stale: Set<String>, readTags: Bool) {
            let toSend = changes(desired: desired, written: written, stale: stale)
            guard !toSend.isEmpty else {
                if readTags { defaults.set(true, forKey: Keys.cleaned) }
                return
            }
            OneSignal.sendTags(toSend, onSuccess: { _ in
                DispatchQueue.main.async {
                    defaults.set(desired, forKey: Keys.written)
                    if readTags { defaults.set(true, forKey: Keys.cleaned) }
                }
            }, onFailure: { error in
                // Tried again on the next change, launch or foreground.
                print("OneSignal tags failed: \(error?.localizedDescription ?? "unknown")")
            })
        }

        guard !defaults.bool(forKey: Keys.cleaned) else { return send(stale: [], readTags: false) }
        OneSignal.getTags({ tags in
            let keys = Set((tags ?? [:]).keys.compactMap { $0 as? String }).filter(isStationTag)
            DispatchQueue.main.async { send(stale: keys, readTags: true) }
        }, onFailure: { _ in
            // Not registered yet, or offline: write what we can, clean later.
            DispatchQueue.main.async { send(stale: [], readTags: false) }
        })
    }
}
