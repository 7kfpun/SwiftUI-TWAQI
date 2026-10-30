//
//  PushManager.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Combine
import Foundation
import UIKit
import UserNotifications

/// The app's half of AQI alerts: asks for permission, registers with APNs,
/// keeps this device's row in Directus current, and opens the station when an
/// alert is tapped. The Worker in workers/twaqi-push-sender decides when to
/// send.
final class PushManager: NSObject, ObservableObject {
    static let shared = PushManager()

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Station whose alert was tapped, until the scene has opened it.
    @Published var pendingStationId: Int?

    private let defaults: UserDefaults
    private let settings = SettingsStore()

    private enum Keys {
        static let deviceToken = "pushDeviceToken"
        static let deviceId = "pushDeviceId"
        static let lastSyncAt = "pushLastSyncAt"
        static let installId = "pushInstallId"
    }

    /// A foreground return refreshes `last_seen_at` at most this often.
    static let syncInterval: TimeInterval = 6 * 60 * 60

    private var tokenWaiters: [CheckedContinuation<String, Error>] = []
    private var deviceTask: Task<Int, Error>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    // MARK: - Lifecycle

    /// From `didFinishLaunching`, before it returns, so a tap that launched
    /// the app is delivered here.
    func start() {
        UNUserNotificationCenter.current().delegate = self
        refresh()
    }

    /// Launch and every return to the foreground. Re-registering is cheap and
    /// hands back the current token, which may have changed.
    func refresh() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorization = settings.authorizationStatus
                if Self.canAlert(settings.authorizationStatus) {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    /// Asks the first time an alert is switched on, which is when the prompt
    /// makes sense to the user. Returns whether alerts can be shown.
    @MainActor
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        authorization = status
        guard Self.canAlert(status) else { return false }
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    static func canAlert(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    // MARK: - Token

    func didRegister(deviceToken data: Data) {
        let token = PushDevicePayload.hexToken(data)
        DispatchQueue.main.async {
            if token != self.defaults.string(forKey: Keys.deviceToken) {
                // Keep the device id: the next sync moves that row, and its
                // alerts, to the new token.
                self.defaults.set(token, forKey: Keys.deviceToken)
                self.defaults.removeObject(forKey: Keys.lastSyncAt)
            }
            let waiters = self.tokenWaiters
            self.tokenWaiters = []
            waiters.forEach { $0.resume(returning: token) }
            self.syncDevice()
        }
    }

    func didFailToRegister(error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            let waiters = self.tokenWaiters
            self.tokenWaiters = []
            waiters.forEach { $0.resume(throwing: PushError.noDeviceToken) }
        }
    }

    // MARK: - Directus

    /// Writes this device's row. `force` for a settings change; otherwise a
    /// recent sync of the same token is enough.
    func syncDevice(force: Bool = false) {
        DispatchQueue.main.async {
            guard self.defaults.string(forKey: Keys.deviceToken) != nil else { return }
            if !force,
               let last = self.defaults.object(forKey: Keys.lastSyncAt) as? Date,
               Date().timeIntervalSince(last) < Self.syncInterval {
                return
            }
            Task { @MainActor in
                do {
                    _ = try await self.upsertDevice()
                } catch {
                    print("Push device sync failed: \(error)")
                }
            }
        }
    }

    /// This device's Directus id, registering first if need be. Throws
    /// `notAuthorized` when the user has turned notifications off.
    @MainActor
    func deviceId() async throws -> Int {
        if defaults.string(forKey: Keys.deviceToken) != nil, defaults.object(forKey: Keys.deviceId) != nil {
            return defaults.integer(forKey: Keys.deviceId)
        }
        guard await requestAuthorization() else { throw PushError.notAuthorized }
        return try await upsertDevice()
    }

    @MainActor
    private func upsertDevice() async throws -> Int {
        if let task = deviceTask {
            return try await task.value
        }
        let task = Task { @MainActor () throws -> Int in
            defer { self.deviceTask = nil }
            guard let config = PushService.Config.current else { throw PushError.notConfigured }
            let token = try await self.currentToken()
            let payload = PushDevicePayload.make(
                deviceToken: token,
                installId: self.installId,
                dndEnabled: self.settings.isDndEnabled,
                dndStart: self.settings.dndStartTime,
                dndEnd: self.settings.dndEndTime
            )
            let knownId = self.defaults.object(forKey: Keys.deviceId) != nil ? self.defaults.integer(forKey: Keys.deviceId) : nil
            let id = try await PushService.upsertDevice(payload, knownId: knownId, config: config)
            // A newer token may have arrived while this one was saving.
            if self.defaults.string(forKey: Keys.deviceToken) == token {
                self.defaults.set(id, forKey: Keys.deviceId)
                self.defaults.set(Date(), forKey: Keys.lastSyncAt)
            }
            return id
        }
        deviceTask = task
        return try await task.value
    }

    /// The stored token, or the next one APNs hands over (15 s at most).
    @MainActor
    private func currentToken() async throws -> String {
        if let token = defaults.string(forKey: Keys.deviceToken) {
            return token
        }
        UIApplication.shared.registerForRemoteNotifications()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            let waiters = self.tokenWaiters
            self.tokenWaiters = []
            waiters.forEach { $0.resume(throwing: PushError.noDeviceToken) }
        }
        return try await withCheckedThrowingContinuation { continuation in
            tokenWaiters.append(continuation)
        }
    }

    /// Random per install; lets the server tell a reinstall from a new phone.
    private var installId: String {
        if let id = defaults.string(forKey: Keys.installId) {
            return id
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: Keys.installId)
        return id
    }

    // MARK: - Subscriptions

    /// This device's alerts for one station, or none before it has registered.
    @MainActor
    func subscriptions(stationId: Int) async throws -> [PushSubscription] {
        guard defaults.object(forKey: Keys.deviceId) != nil,
              let config = PushService.Config.current
        else {
            return []
        }
        let device = defaults.integer(forKey: Keys.deviceId)
        return try await PushService.subscriptions(device: device, config: config)
            .filter { $0.stationId == String(stationId) }
    }

    @MainActor
    func save(_ subscription: PushSubscription) async throws -> Int {
        guard let config = PushService.Config.current else { throw PushError.notConfigured }
        let device = try await deviceId()
        return try await PushService.save(subscription, device: device, config: config)
    }

    /// Help's "cancel all": archives every alert on this device.
    @MainActor
    func cancelAllAlerts() async throws {
        guard defaults.object(forKey: Keys.deviceId) != nil,
              let config = PushService.Config.current
        else {
            return
        }
        let device = defaults.integer(forKey: Keys.deviceId)
        let ids = try await PushService.subscriptions(device: device, config: config).compactMap(\.id)
        try await PushService.archive(subscriptions: ids, config: config)
    }

    // MARK: - Tap

    /// `station_id` from an alert's payload; the Worker sends a number.
    static func stationId(from userInfo: [AnyHashable: Any]) -> Int? {
        switch userInfo["station_id"] {
        case let id as Int:
            return id
        case let id as NSNumber:
            return id.intValue
        case let id as String:
            return Int(id)
        default:
            return nil
        }
    }
}

extension PushManager: UNUserNotificationCenterDelegate {
    /// Show alerts that arrive while the app is open, too.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let stationId = Self.stationId(from: response.notification.request.content.userInfo) {
            DispatchQueue.main.async {
                self.pendingStationId = stationId
                TrackingManager.logEvent(eventName: "push_alert_opened", parameters: ["stationId": stationId])
            }
        }
        completionHandler()
    }
}
