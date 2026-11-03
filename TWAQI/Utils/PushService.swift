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
    /// The app's language: the one chosen under Help, else iOS's ("zh-Hant",
    /// "en"). The sender writes each alert in it.
    var locale: String?
    /// Taiwan Air Pro is active (subscription or lifetime), as last read
    /// from StoreKit on this device.
    var isPro: Bool
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
        case isPro = "is_pro"
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
        try values.encode(isPro, forKey: .isPro)
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
        isPro: Bool = false,
        language: AppLanguage = .current,
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
            // Help's choice wins over the one iOS picked for the app.
            locale: language.localeIdentifier ?? bundle.preferredLocalizations.first ?? Locale.current.identifier,
            isPro: isPro,
            lastSeenAt: ISO8601DateFormatter().string(from: now),
            dndEnabled: dndEnabled,
            dndStart: hourMinute(dndStart, calendar: calendar),
            dndEnd: hourMinute(dndEnd, calendar: calendar),
            timezone: calendar.timeZone.identifier
        )
    }

    /// What, besides the tokens, makes the row out of date when it changes:
    /// the language alerts are written in, Pro, and the do-not-disturb window
    /// with its time zone. Saved only after a write succeeds, so a failed one
    /// is retried on the next flush, even after a relaunch.
    var profile: String {
        [locale ?? "", String(isPro), String(dndEnabled), dndStart, dndEnd, timezone].joined(separator: "|")
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
    /// `PushApiUrl` is missing from the build's xcconfig.
    case notConfigured
    case noDeviceToken
    /// The Keychain wouldn't hold the device id.
    case noDeviceId
    case offline
    case server(statusCode: Int)
    case network
}

/// The push API on the `twaqi-push-sender` Worker (FOX-13 / FOX-37 M5). The
/// app holds no Directus token for the push collections: each request names
/// this install's Keychain device id and carries its secret, and the Worker
/// reads and writes only this device's rows. Nothing is hard-deleted: an
/// alert the user clears is archived.
enum PushService {
    struct Config {
        var baseURL: URL
        var deviceId: String
        var secret: String

        /// `PushApiUrl` from the build's xcconfig, with this install's
        /// Keychain id and secret. Nil when either is missing.
        static var current: Config? {
            guard let deviceId = PushDeviceIdentity.id(), let secret = PushDeviceIdentity.secret() else { return nil }
            return make(baseURL: getEnv("PushApiUrl"), deviceId: deviceId, secret: secret)
        }

        static func make(baseURL: String?, deviceId: String, secret: String) -> Config? {
            guard let baseURL = baseURL?.trimmingCharacters(in: .whitespaces), !baseURL.isEmpty,
                  let url = URL(string: baseURL), url.scheme == "https"
            else {
                return nil
            }
            return Config(baseURL: url, deviceId: deviceId, secret: secret)
        }
    }

    // MARK: - Devices

    /// Creates or updates this device's row and returns its id. The Worker
    /// finds it by the device id (or adopts a row made for this APNs token
    /// before there was one).
    static func upsertDevice(_ payload: PushDevicePayload, config: Config, session: URLSession = .shared) async throws -> Int {
        let data = try await send(makeRequest(config: config, method: "PUT", path: "app/v1/device", body: payload), session: session)
        return try JSONDecoder().decode(IdOnly.self, from: data).id
    }

    /// What a reinstall restores from: this device's row (found by device id,
    /// else by `deviceToken`) with its do-not-disturb window, and its live
    /// alerts. Nil device when there is none.
    static func restore(deviceToken: String, config: Config, session: URLSession = .shared) async throws -> Restored {
        let request = makeRequest(config: config, method: "GET", path: "app/v1/device", query: [("device_token", deviceToken)])
        return try JSONDecoder().decode(Restored.self, from: try await send(request, session: session))
    }

    struct Restored: Decodable, Equatable {
        let device: StoredDevice?
        let subscriptions: [PushSubscription]
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

    // MARK: - Alerts

    /// Brings one station's alerts in Directus in line with `alerts`: on
    /// updates (or makes) its row, off archives it. The Worker does the rows.
    static func reconcile(stationId: String, siteId: String?, alerts: StationAlerts, config: Config, session: URLSession = .shared) async throws {
        let body = StationChange(siteId: siteId, above: alerts.above, below: alerts.below)
        _ = try await send(makeRequest(config: config, method: "PUT", path: "app/v1/stations/\(stationId)", body: body), session: session)
    }

    /// Help's "cancel all": archives every live alert of this device.
    static func archiveAll(config: Config, session: URLSession = .shared) async throws {
        _ = try await send(makeRequest(config: config, method: "POST", path: "app/v1/archive-all"), session: session)
    }

    /// A station's two alerts: a threshold when on, null when off.
    struct StationChange: Encodable, Equatable {
        var siteId: String?
        var above: Int?
        var below: Int?

        enum CodingKeys: String, CodingKey {
            case above, below
            case siteId = "site_id"
        }

        // Nulls are sent: null is "off", not "unchanged".
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encodeIfPresent(siteId, forKey: .siteId)
            try values.encode(above, forKey: .above)
            try values.encode(below, forKey: .below)
        }
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
        request.setValue(config.deviceId, forHTTPHeaderField: "X-Device-Id")
        request.setValue("Bearer \(config.secret)", forHTTPHeaderField: "Authorization")
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

    private struct IdOnly: Decodable { let id: Int }
}
