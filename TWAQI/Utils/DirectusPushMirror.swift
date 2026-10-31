//
//  DirectusPushMirror.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Combine
import Foundation
import Security

/// Keeps the push settings — each station's alerts and the do-not-disturb
/// window — in Directus (`twaqi_push_devices`, `twaqi_push_subscriptions`),
/// where the FCM sender reads them.
///
/// The station page and Help write here; this is the only store for alerts.
/// Changes are kept in `UserDefaults` first and written to Directus after:
/// a failure is logged and retried on the next change, launch or token
/// change, and never reaches the user.
///
/// The device row is keyed by `PushDeviceIdentity` (a Keychain UUID) and
/// carries the APNs token and the FCM registration token, both handed over
/// by `AppDelegate`. A row is only made once the device has an alert switched
/// on; after that it follows every token change.
@MainActor
final class DirectusPushMirror: ObservableObject {
    static let shared = DirectusPushMirror()

    /// A launch refreshes `last_seen_at` at most this often.
    static let deviceRefreshInterval: TimeInterval = 6 * 60 * 60
    /// Sliders send a value per step; write once they settle.
    static let debounce: UInt64 = 800_000_000

    /// Changes when alerts are restored from Directus, so an open station
    /// page can show them.
    @Published private(set) var restoredAt: Date?

    private let defaults: UserDefaults
    private let settings = SettingsStore()

    private enum Keys {
        static let deviceId = "directusPushDeviceId"
        static let deviceToken = "directusPushDeviceToken"
        static let fcmToken = "directusPushFcmToken"
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
    private var forceDevice = false
    private var timers: [String: Task<Void, Never>] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Entry points

    /// At launch: catches up on anything an earlier launch couldn't write,
    /// once the tokens arrive.
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

    /// A station's alerts as the user last set them, written or not.
    func alerts(stationId: Int) -> StationAlerts {
        load([String: StationAlerts].self, Keys.wanted)?[String(stationId)] ?? .off
    }

    /// Stations with at least one alert on, written or not.
    var stationIdsWithAlerts: Set<String> {
        Set((load([String: StationAlerts].self, Keys.wanted) ?? [:]).filter { !$0.value.isOff }.keys)
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
            mirror.forceDevice = true
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
        guard let config = PushService.Config.current else { return }
        // APNs hasn't registered yet; `apnsTokenChanged` brings us back.
        guard let token = apnsToken else { return }

        if !defaults.bool(forKey: Keys.restored) {
            do {
                try await restore(token: token, config: config)
            } catch {
                // Writing now could overwrite the row being restored from.
                print("Directus push: restore failed: \(error)")
                return
            }
        }

        if defaults.bool(forKey: Keys.archiveAll), defaults.object(forKey: Keys.deviceId) != nil {
            let device = defaults.integer(forKey: Keys.deviceId)
            do {
                let ids = try await PushService.subscriptions(device: device, config: config).compactMap(\.id)
                try await PushService.archive(subscriptions: ids, config: config)
                defaults.set(false, forKey: Keys.archiveAll)
                // Everything is archived now; only changes made since remain.
                let wanted = (load([String: StationAlerts].self, Keys.wanted) ?? [:]).filter { !$0.value.isOff }
                save(wanted, Keys.wanted)
                save([String: StationAlerts](), Keys.synced)
            } catch {
                print("Directus push: cancel all failed: \(error)")
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
        guard hasDevice || pending.values.contains(where: { !$0.isOff }) else { return }

        let device: Int
        do {
            device = try await deviceId(token: token, fcmToken: fcmToken, config: config)
        } catch {
            print("Directus push: device sync failed: \(error)")
            return
        }

        // A new row starts with no alerts: write everything again.
        let refreshed = self.synced
        let siteIds = load([String: String].self, Keys.siteIds) ?? [:]
        for (key, alerts) in wanted where refreshed[key] != alerts {
            do {
                try await PushService.reconcile(stationId: key, siteId: siteIds[key], alerts: alerts, device: device, config: config)
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
            }
        }
    }

    /// Once per install: finds the row this phone already has — from before a
    /// reinstall (same Keychain id), or one made for its APNs token — and
    /// takes its alerts, and on a fresh install its do-not-disturb window.
    /// Local changes not yet written win over what's restored.
    private func restore(token: String, config: PushService.Config) async throws {
        guard let stableId = PushDeviceIdentity.id() else { throw PushError.noDeviceId }
        let isFreshInstall = defaults.object(forKey: Keys.deviceId) == nil

        var stored = try await PushService.storedDevice(field: PushDevicePayload.deviceIdField, value: stableId, config: config)
        if stored == nil {
            stored = try await PushService.storedDevice(field: "device_token", value: token, config: config)
        }
        guard let stored = stored else {
            defaults.set(true, forKey: Keys.restored)
            return
        }

        let remote = StationAlerts.byStation(try await PushService.subscriptions(device: stored.id, config: config))

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
        for (key, alerts) in remote where wanted[key] == nil {
            wanted[key] = alerts
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
        restoredAt = Date()
    }

    /// This device's row, created or refreshed when its tokens, DND or age
    /// call for it.
    private func deviceId(token: String, fcmToken: String?, config: PushService.Config) async throws -> Int {
        let knownId = defaults.object(forKey: Keys.deviceId) != nil ? defaults.integer(forKey: Keys.deviceId) : nil
        guard let stableId = PushDeviceIdentity.id() else { throw PushError.noDeviceId }
        let lastSync = defaults.object(forKey: Keys.lastDeviceSyncAt) as? Date
        if let knownId = knownId,
           !forceDevice,
           defaults.string(forKey: Keys.deviceToken) == token,
           fcmToken == nil || defaults.string(forKey: Keys.fcmToken) == fcmToken,
           let lastSync = lastSync,
           Date().timeIntervalSince(lastSync) < Self.deviceRefreshInterval {
            return knownId
        }

        forceDevice = false
        let payload = PushDevicePayload.make(
            deviceId: stableId,
            deviceToken: token,
            fcmToken: fcmToken,
            dndEnabled: settings.isDndEnabled,
            dndStart: settings.dndStartTime,
            dndEnd: settings.dndEndTime
        )
        let id = try await PushService.upsertDevice(payload, config: config)
        if id != knownId {
            save([String: StationAlerts](), Keys.synced)
        }
        defaults.set(id, forKey: Keys.deviceId)
        defaults.set(token, forKey: Keys.deviceToken)
        if let fcmToken = fcmToken {
            defaults.set(fcmToken, forKey: Keys.fcmToken)
        }
        defaults.set(Date(), forKey: Keys.lastDeviceSyncAt)
        return id
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

    /// The stored id, made on first use. Nil only if the Keychain refuses.
    static func id() -> String? {
        if let existing = read() {
            return existing
        }
        let made = UUID().uuidString.lowercased()
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
            return read()
        case let status:
            print("Directus push: Keychain refused the device id (\(status))")
            return nil
        }
    }

    private static func read() -> String? {
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
              let id = String(data: data, encoding: .utf8),
              !id.isEmpty
        else {
            return nil
        }
        return id
    }
}
