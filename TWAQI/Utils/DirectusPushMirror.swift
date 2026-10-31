//
//  DirectusPushMirror.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import OneSignal
import Security

/// Copies the push settings OneSignal holds as tags — each station's alerts
/// and the do-not-disturb window — into Directus (`twaqi_push_devices`,
/// `twaqi_push_subscriptions`), ready for the app's own sender to take over.
///
/// OneSignal is still the live sender and the source of truth. Everything here
/// is best-effort and runs after, never before, the OneSignal write: a Directus
/// failure is logged and retried on the next change or launch, and never
/// reaches the user.
///
/// The device row is keyed by `PushDeviceIdentity` (a Keychain UUID), and
/// carries the APNs token OneSignal registered plus OneSignal's player id, so
/// this adds no permission prompt or registration of its own. A row is only
/// made once the device has an alert switched on.
@MainActor
final class DirectusPushMirror: NSObject {
    static let shared = DirectusPushMirror()

    /// A launch refreshes `last_seen_at` at most this often.
    static let deviceRefreshInterval: TimeInterval = 6 * 60 * 60
    /// Sliders send a value per step; write once they settle.
    static let debounce: UInt64 = 800_000_000

    private let defaults: UserDefaults
    private let settings = SettingsStore()

    private enum Keys {
        static let deviceId = "directusPushDeviceId"
        static let deviceToken = "directusPushDeviceToken"
        static let lastDeviceSyncAt = "directusPushLastDeviceSyncAt"
        /// Station id → alerts as OneSignal has them.
        static let wanted = "directusPushWantedAlerts"
        /// Station id → alerts as last written to Directus.
        static let synced = "directusPushSyncedAlerts"
        static let siteIds = "directusPushSiteIds"
        /// Help's "cancel all" is still to reach Directus.
        static let archiveAll = "directusPushArchiveAll"
    }

    private var isFlushing = false
    private var flushAgain = false
    private var forceDevice = false
    private var timers: [String: Task<Void, Never>] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    // MARK: - Entry points

    /// After OneSignal is initialised: follows its token, and catches up on
    /// anything an earlier launch couldn't write.
    func start() {
        OneSignal.add(self as OSSubscriptionObserver)
        flush()
    }

    /// The station row's alerts, after OneSignal has been sent the same.
    /// `settled` skips the wait, for values read rather than dragged.
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

    /// The station's alerts as last sent to OneSignal, from this mirror's
    /// record: still to write, else written. Nil when there is no record.
    /// Only reads defaults, so callable from any thread.
    nonisolated static func knownAlerts(stationId: Int, defaults: UserDefaults = .standard) -> StationAlerts? {
        let key = String(stationId)
        for record in [Keys.wanted, Keys.synced] {
            if let alerts = defaults.data(forKey: record)
                .flatMap({ try? JSONDecoder().decode([String: StationAlerts].self, from: $0) })?[key] {
                return alerts
            }
        }
        return nil
    }

    // MARK: - Sync

    private var synced: [String: StationAlerts] {
        load([String: StationAlerts].self, Keys.synced) ?? [:]
    }

    /// Writes whatever differs between OneSignal's settings and Directus.
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
                print("Directus push mirror: cancel all failed: \(error)")
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

        guard let state = OneSignal.getDeviceState(), let token = state.pushToken, !token.isEmpty else {
            // OneSignal hasn't registered yet; its observer brings us back.
            return
        }

        let device: Int
        do {
            device = try await deviceId(token: token, playerId: state.userId, config: config)
        } catch {
            print("Directus push mirror: device sync failed: \(error)")
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
                print("Directus push mirror: station \(key) failed: \(error)")
            }
        }
    }

    /// This device's row, created or refreshed when its token, DND or age
    /// call for it.
    private func deviceId(token: String, playerId: String?, config: PushService.Config) async throws -> Int {
        let knownId = defaults.object(forKey: Keys.deviceId) != nil ? defaults.integer(forKey: Keys.deviceId) : nil
        guard let stableId = PushDeviceIdentity.id() else { throw PushError.noDeviceId }
        let lastSync = defaults.object(forKey: Keys.lastDeviceSyncAt) as? Date
        if let knownId = knownId,
           !forceDevice,
           defaults.string(forKey: Keys.deviceToken) == token,
           let lastSync = lastSync,
           Date().timeIntervalSince(lastSync) < Self.deviceRefreshInterval {
            return knownId
        }

        forceDevice = false
        let payload = PushDevicePayload.make(
            deviceId: stableId,
            deviceToken: token,
            externalId: playerId,
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

extension DirectusPushMirror: OSSubscriptionObserver {
    /// OneSignal calls this off the main thread when it gets or changes the
    /// APNs token.
    nonisolated func onOSSubscriptionChanged(_ stateChanges: OSSubscriptionStateChanges) {
        guard stateChanges.to.pushToken != stateChanges.from.pushToken else { return }
        Task { @MainActor in
            self.flush()
        }
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
            print("Directus push mirror: Keychain refused the device id (\(status))")
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
