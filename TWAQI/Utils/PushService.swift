//
//  PushService.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// Which APNs host a device token belongs to. Xcode debug builds get sandbox
/// tokens; TestFlight and App Store builds get production ones.
enum PushEnvironment: String, Codable {
    case sandbox
    case production

    static var current: PushEnvironment {
        #if targetEnvironment(simulator)
        return .sandbox
        #else
        let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
        return from(provisioningProfile: profile)
        #endif
    }

    /// Reads `aps-environment` from the embedded provisioning profile. App
    /// Store and TestFlight builds carry no profile, and are production.
    static func from(provisioningProfile data: Data?) -> PushEnvironment {
        guard
            let data = data,
            let start = data.range(of: Data("<?xml".utf8)),
            let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
            let plist = try? PropertyListSerialization.propertyList(
                from: data.subdata(in: start.lowerBound..<end.upperBound),
                format: nil
            ) as? [String: Any],
            let entitlements = plist["Entitlements"] as? [String: Any],
            let aps = entitlements["aps-environment"] as? String
        else {
            return .production
        }
        return aps == "development" ? .sandbox : .production
    }
}

/// The station page's two alerts, by the names its settings have always used.
enum NotificationTypes: String {
    case pollution
    case cleanliness
}

enum PushDirection: String, Codable, CaseIterable {
    /// AQI more than the threshold: the `pollution` alert.
    case above
    /// AQI less than the threshold: the `cleanliness` alert.
    case below

    init(_ type: NotificationTypes) {
        switch type {
        case .pollution: self = .above
        case .cleanliness: self = .below
        }
    }
}

/// The app's side of a Directus `twaqi_push_devices` item: everything but the
/// sender's bookkeeping.
struct PushDevicePayload: Encodable, Equatable {
    /// Column holding the app's stable device id, the upsert key.
    static let deviceIdField = CodingKeys.deviceId.rawValue

    /// Stable per device (a Keychain UUID, kept across reinstalls), unlike
    /// the APNs and FCM tokens, which rotate.
    var deviceId: String
    /// The APNs token, hex. Kept alongside the FCM token so a row is still
    /// matched to the phone, and reachable directly over APNs if need be.
    var deviceToken: String
    /// The Firebase Cloud Messaging registration token: what the sender
    /// addresses. Nil until Messaging has one; left out rather than cleared.
    var fcmToken: String?
    var environment: PushEnvironment
    var appVersion: String?
    var locale: String?
    var lastSeenAt: String
    var dndEnabled: Bool
    /// "HH:mm", wall-clock time in `timezone`.
    var dndStart: String
    var dndEnd: String
    var timezone: String
    /// Always false: a token seen again is alive, even if APNs once rejected it.
    var archived = false

    enum CodingKeys: String, CodingKey {
        case environment, locale, timezone, archived
        /// See `deviceIdField`.
        case deviceId = "device_id"
        case deviceToken = "device_token"
        case fcmToken = "fcm_token"
        case appVersion = "app_version"
        case lastSeenAt = "last_seen_at"
        case dndEnabled = "dnd_enabled"
        case dndStart = "dnd_start"
        case dndEnd = "dnd_end"
    }

    // Never writes `external_id`: that held OneSignal's player id and is left
    // as it was. Leaves `fcm_token` alone, rather than clearing it, until
    // Messaging has one.
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(deviceId, forKey: .deviceId)
        try values.encode(deviceToken, forKey: .deviceToken)
        try values.encodeIfPresent(fcmToken, forKey: .fcmToken)
        try values.encode(environment, forKey: .environment)
        try values.encodeIfPresent(appVersion, forKey: .appVersion)
        try values.encodeIfPresent(locale, forKey: .locale)
        try values.encode(lastSeenAt, forKey: .lastSeenAt)
        try values.encode(dndEnabled, forKey: .dndEnabled)
        try values.encode(dndStart, forKey: .dndStart)
        try values.encode(dndEnd, forKey: .dndEnd)
        try values.encode(timezone, forKey: .timezone)
        try values.encode(archived, forKey: .archived)
    }

    static func make(
        deviceId: String,
        deviceToken: String,
        fcmToken: String?,
        dndEnabled: Bool,
        dndStart: Date,
        dndEnd: Date,
        now: Date = Date(),
        environment: PushEnvironment = .current,
        bundle: Bundle = .main,
        calendar: Calendar = .current
    ) -> PushDevicePayload {
        PushDevicePayload(
            deviceId: deviceId,
            deviceToken: deviceToken,
            fcmToken: fcmToken,
            environment: environment,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
            // The app's language, not the region: alert text follows it.
            locale: bundle.preferredLocalizations.first ?? Locale.current.identifier,
            lastSeenAt: ISO8601DateFormatter().string(from: now),
            dndEnabled: dndEnabled,
            dndStart: hourMinute(dndStart, calendar: calendar),
            dndEnd: hourMinute(dndEnd, calendar: calendar),
            timezone: calendar.timeZone.identifier
        )
    }

    static func hourMinute(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// One alert, a Directus `twaqi_push_subscriptions` item. A station has at
/// most one live (not archived) item per direction.
struct PushSubscription: Codable, Equatable {
    var id: Int?
    var device: Int?
    /// The AQI API's station id. A string column in Directus.
    var stationId: String
    /// MOENV SiteId of the station's cam, when it has one. Never used to
    /// build an AQI request: the two numberings are unrelated.
    var siteId: String?
    var metric = "aqi"
    var direction: PushDirection
    /// An integer column; the app's slider steps by 1.
    var threshold: Int
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, device, metric, direction, threshold, enabled
        case stationId = "station_id"
        case siteId = "site_id"
    }

    init(id: Int? = nil, device: Int? = nil, stationId: String, siteId: String?, direction: PushDirection, threshold: Int, enabled: Bool) {
        self.id = id
        self.device = device
        self.stationId = stationId
        self.siteId = siteId
        self.direction = direction
        self.threshold = threshold
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(Int.self, forKey: .id)
        device = try? values.decodeIfPresent(Int.self, forKey: .device)
        if let text = try? values.decode(String.self, forKey: .stationId) {
            stationId = text
        } else {
            stationId = String(try values.decode(Int.self, forKey: .stationId))
        }
        siteId = try values.decodeIfPresent(String.self, forKey: .siteId)
        metric = try values.decodeIfPresent(String.self, forKey: .metric) ?? "aqi"
        direction = try values.decode(PushDirection.self, forKey: .direction)
        if let whole = try? values.decode(Int.self, forKey: .threshold) {
            threshold = whole
        } else {
            threshold = Int(try values.decode(Double.self, forKey: .threshold).rounded())
        }
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    }

    // Leaves site_id alone rather than clearing it when the cam is unknown.
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(id, forKey: .id)
        try values.encodeIfPresent(device, forKey: .device)
        try values.encode(stationId, forKey: .stationId)
        try values.encodeIfPresent(siteId, forKey: .siteId)
        try values.encode(metric, forKey: .metric)
        try values.encode(direction, forKey: .direction)
        try values.encode(threshold, forKey: .threshold)
        try values.encode(enabled, forKey: .enabled)
    }
}

/// A station's two alerts as Directus holds them: a threshold when on, nil
/// when off.
struct StationAlerts: Codable, Equatable {
    var above: Int?
    var below: Int?

    static let off = StationAlerts()

    init(above: Int? = nil, below: Int? = nil) {
        self.above = above
        self.below = below
    }

    /// From the station row's switches: pollution is the above alert,
    /// cleanliness the below one.
    init(_ setting: StationAlertSetting) {
        above = setting.isPollutionNotificationEnabled ? Int(setting.pollutionTherhold.rounded()) : nil
        below = setting.isCleanlinessNotificationEnabled ? Int(setting.cleanlinessTherhold.rounded()) : nil
    }

    var isOff: Bool { above == nil && below == nil }

    /// Live subscriptions grouped by station. Of several rows for one
    /// direction (an earlier race), the first wins, as in `reconcile`.
    static func byStation(_ subscriptions: [PushSubscription]) -> [String: StationAlerts] {
        var result: [String: StationAlerts] = [:]
        for item in subscriptions where item.enabled {
            var alerts = result[item.stationId] ?? .off
            switch item.direction {
            case .above where alerts.above == nil: alerts.above = item.threshold
            case .below where alerts.below == nil: alerts.below = item.threshold
            default: break
            }
            result[item.stationId] = alerts
        }
        return result.filter { !$0.value.isOff }
    }

    func threshold(_ direction: PushDirection) -> Int? {
        switch direction {
        case .above: return above
        case .below: return below
        }
    }
}

enum PushError: Error, Equatable {
    /// The Directus URL or token is missing from the build's xcconfig.
    case notConfigured
    case noDeviceToken
    /// The Keychain wouldn't hold the device id.
    case noDeviceId
    case offline
    case server(statusCode: Int)
    case network
}

/// Directus REST for the push collections, with the app's static token.
/// The token may create, read and update, never delete: an alert the user
/// clears is archived.
enum PushService {
    static let devicesPath = "items/twaqi_push_devices"
    static let subscriptionsPath = "items/twaqi_push_subscriptions"

    struct Config {
        var baseURL: URL
        var token: String

        /// `DirectusPushToken` when the build sets one, else the feedback
        /// token, whose role also covers the push collections.
        static var current: Config? {
            make(baseURL: getEnv("DirectusUrl"), pushToken: getEnv("DirectusPushToken"), feedbackToken: getEnv("DirectusFeedbackToken"))
        }

        static func make(baseURL: String?, pushToken: String?, feedbackToken: String?) -> Config? {
            make(
                baseURL: baseURL,
                token: [pushToken, feedbackToken]
                    .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty }
            )
        }

        static func make(baseURL: String?, token: String?) -> Config? {
            guard let baseURL = baseURL?.trimmingCharacters(in: .whitespaces), !baseURL.isEmpty,
                  let token = token?.trimmingCharacters(in: .whitespaces), !token.isEmpty,
                  let url = URL(string: baseURL)
            else {
                return nil
            }
            return Config(baseURL: url, token: token)
        }
    }

    // MARK: - Devices

    /// Creates or updates this device's row and returns its id. The row is
    /// found by the app's stable device id, never by APNs token, which
    /// rotates. A row this device's token already has (from a build before the
    /// device id) is adopted instead of tripping the token's unique index. A
    /// lost race to create falls back to the row the other request made.
    static func upsertDevice(_ payload: PushDevicePayload, config: Config, session: URLSession = .shared) async throws -> Int {
        let byDeviceId = (PushDevicePayload.deviceIdField, payload.deviceId)
        let byToken = ("device_token", payload.deviceToken)

        for (field, value) in [byDeviceId, byToken] {
            if let id = try await deviceRowId(field: field, value: value, config: config, session: session) {
                _ = try await send(makeRequest(config: config, method: "PATCH", path: "\(devicesPath)/\(id)", query: [("fields", "id")], body: payload), session: session)
                return id
            }
        }

        do {
            let data = try await send(makeRequest(config: config, method: "POST", path: devicesPath, query: [("fields", "id")], body: payload), session: session)
            return try JSONDecoder().decode(Item<IdOnly>.self, from: data).data.id
        } catch PushError.server(let status) where status == 400 {
            if let id = try await deviceRowId(field: byDeviceId.0, value: byDeviceId.1, config: config, session: session) {
                return id
            }
            throw PushError.server(statusCode: status)
        }
    }

    /// The first row whose `field` equals `value`.
    static func deviceRowId(field: String, value: String, config: Config, session: URLSession = .shared) async throws -> Int? {
        let request = makeRequest(config: config, method: "GET", path: devicesPath, query: [
            ("fields", "id"),
            ("filter[\(field)][_eq]", value),
            ("sort", "id"),
            ("limit", "1"),
        ])
        let data = try await send(request, session: session)
        return try JSONDecoder().decode(Items<IdOnly>.self, from: data).data.first?.id
    }

    /// The first row whose `field` equals `value`, with its do-not-disturb
    /// window: what a reinstall restores from.
    static func storedDevice(field: String, value: String, config: Config, session: URLSession = .shared) async throws -> StoredDevice? {
        let request = makeRequest(config: config, method: "GET", path: devicesPath, query: [
            ("fields", "id,dnd_enabled,dnd_start,dnd_end"),
            ("filter[\(field)][_eq]", value),
            ("sort", "id"),
            ("limit", "1"),
        ])
        let data = try await send(request, session: session)
        return try JSONDecoder().decode(Items<StoredDevice>.self, from: data).data.first
    }

    struct StoredDevice: Decodable, Equatable {
        let id: Int
        let dndEnabled: Bool?
        /// "HH:mm" (Directus may add seconds).
        let dndStart: String?
        let dndEnd: String?

        enum CodingKeys: String, CodingKey {
            case id
            case dndEnabled = "dnd_enabled"
            case dndStart = "dnd_start"
            case dndEnd = "dnd_end"
        }

        /// "HH:mm" or "HH:mm:ss" as today's date at that time.
        static func time(_ text: String?, calendar: Calendar = .current, now: Date = Date()) -> Date? {
            guard let parts = text?.split(separator: ":").compactMap({ Int($0) }),
                  parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1])
            else {
                return nil
            }
            return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now)
        }
    }

    // MARK: - Subscriptions

    /// The device's live (not archived) alerts, for one station or all.
    static func subscriptions(device: Int, stationId: String? = nil, config: Config, session: URLSession = .shared) async throws -> [PushSubscription] {
        var query: [(String, String)] = [
            ("fields", "id,device,station_id,site_id,metric,direction,threshold,enabled"),
            ("filter[device][_eq]", String(device)),
            ("filter[archived][_eq]", "false"),
            ("sort", "id"),
            ("limit", "-1"),
        ]
        if let stationId = stationId {
            query.append(("filter[station_id][_eq]", stationId))
        }
        let data = try await send(makeRequest(config: config, method: "GET", path: subscriptionsPath, query: query), session: session)
        return try JSONDecoder().decode(Items<PushSubscription>.self, from: data).data
    }

    /// Creates the subscription, or updates the one with its id. Returns the id.
    static func save(_ subscription: PushSubscription, device: Int, config: Config, session: URLSession = .shared) async throws -> Int {
        var item = subscription
        item.device = device
        if let id = item.id {
            let changes = SubscriptionChanges(siteId: item.siteId, threshold: item.threshold, enabled: item.enabled)
            _ = try await send(makeRequest(config: config, method: "PATCH", path: "\(subscriptionsPath)/\(id)", query: [("fields", "id")], body: changes), session: session)
            return id
        }
        item.id = nil
        let data = try await send(makeRequest(config: config, method: "POST", path: subscriptionsPath, query: [("fields", "id")], body: item), session: session)
        return try JSONDecoder().decode(Item<IdOnly>.self, from: data).data.id
    }

    /// Soft-deletes: the rows stay, with `archived` set and alerts off.
    static func archive(subscriptions ids: [Int], config: Config, session: URLSession = .shared) async throws {
        guard !ids.isEmpty else { return }
        let body = BatchUpdate(keys: ids, data: ArchiveChanges())
        _ = try await send(makeRequest(config: config, method: "PATCH", path: subscriptionsPath, query: [("fields", "id")], body: body), session: session)
    }

    /// Brings one station's live rows in line with `alerts`: each alert that
    /// is on updates its row (or creates one); each that is off has its rows
    /// archived. Extra rows for a direction, from an earlier race, are archived.
    static func reconcile(
        stationId: String,
        siteId: String?,
        alerts: StationAlerts,
        device: Int,
        config: Config,
        session: URLSession = .shared
    ) async throws {
        let existing = try await subscriptions(device: device, stationId: stationId, config: config, session: session)
        let plan = plan(existing: existing, stationId: stationId, siteId: siteId, alerts: alerts)
        for item in plan.save {
            _ = try await save(item, device: device, config: config, session: session)
        }
        try await archive(subscriptions: plan.archive, config: config, session: session)
    }

    /// The writes `reconcile` makes, apart from the network.
    static func plan(existing: [PushSubscription], stationId: String, siteId: String?, alerts: StationAlerts) -> (save: [PushSubscription], archive: [Int]) {
        var saves: [PushSubscription] = []
        var archives: [Int] = []
        for direction in PushDirection.allCases {
            let rows = existing.filter { $0.direction == direction }
            guard let threshold = alerts.threshold(direction) else {
                archives += rows.compactMap(\.id)
                continue
            }
            let keep = rows.first
            archives += rows.dropFirst().compactMap(\.id)
            if let keep = keep, keep.threshold == threshold, keep.enabled, siteId == nil || keep.siteId == siteId {
                continue
            }
            saves.append(PushSubscription(
                id: keep?.id,
                stationId: stationId,
                siteId: siteId,
                direction: direction,
                threshold: threshold,
                enabled: true
            ))
        }
        return (saves, archives)
    }

    // MARK: - HTTP

    static func makeRequest(
        config: Config,
        method: String,
        path: String,
        query: [(String, String)] = [],
        body: Encodable? = nil
    ) -> URLRequest {
        var components = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        return request
    }

    private static func send(_ request: URLRequest, session: URLSession) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError
            where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            throw PushError.offline
        } catch {
            throw PushError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw PushError.network
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PushError.server(statusCode: http.statusCode)
        }
        return data
    }

    private struct Item<T: Decodable>: Decodable { let data: T }
    private struct Items<T: Decodable>: Decodable { let data: [T] }
    private struct IdOnly: Decodable { let id: Int }

    struct SubscriptionChanges: Encodable, Equatable {
        var siteId: String?
        var threshold: Int
        var enabled: Bool

        enum CodingKeys: String, CodingKey {
            case threshold, enabled
            case siteId = "site_id"
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encodeIfPresent(siteId, forKey: .siteId)
            try values.encode(threshold, forKey: .threshold)
            try values.encode(enabled, forKey: .enabled)
        }
    }

    struct ArchiveChanges: Encodable, Equatable {
        var archived = true
        var enabled = false
    }

    struct BatchUpdate<T: Encodable>: Encodable {
        let keys: [Int]
        let data: T
    }
}
