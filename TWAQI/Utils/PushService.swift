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

enum PushDirection: String, Codable {
    /// AQI more than the threshold.
    case above
    /// AQI less than the threshold.
    case below
}

/// The app's side of a Directus `twaqi_push_devices` item: everything but
/// `archived` handling on the server and the Worker's bookkeeping.
struct PushDevicePayload: Encodable, Equatable {
    var deviceToken: String
    var environment: PushEnvironment
    var appVersion: String?
    var locale: String?
    var lastSeenAt: String
    var installId: String
    var dndEnabled: Bool
    /// "HH:mm", wall-clock time in `timezone`.
    var dndStart: String
    var dndEnd: String
    var timezone: String
    /// Always false: a token seen again is alive, even if APNs once rejected it.
    var archived = false

    enum CodingKeys: String, CodingKey {
        case environment, locale, timezone, archived
        case deviceToken = "device_token"
        case appVersion = "app_version"
        case lastSeenAt = "last_seen_at"
        case installId = "install_id"
        case dndEnabled = "dnd_enabled"
        case dndStart = "dnd_start"
        case dndEnd = "dnd_end"
    }

    static func make(
        deviceToken: String,
        installId: String,
        dndEnabled: Bool,
        dndStart: Date,
        dndEnd: Date,
        now: Date = Date(),
        environment: PushEnvironment = .current,
        bundle: Bundle = .main,
        calendar: Calendar = .current
    ) -> PushDevicePayload {
        PushDevicePayload(
            deviceToken: deviceToken,
            environment: environment,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
            // The app's language, not the region: the Worker picks the station
            // name to match the alert text, which iOS localizes in this language.
            locale: bundle.preferredLocalizations.first ?? Locale.current.identifier,
            lastSeenAt: ISO8601DateFormatter().string(from: now),
            installId: installId,
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

    /// APNs hands the token over as bytes; Directus and APNs both want hex.
    static func hexToken(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

/// One alert, a Directus `twaqi_push_subscriptions` item. Each station has
/// at most one per direction.
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
    var threshold: Double
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, device, metric, direction, threshold, enabled
        case stationId = "station_id"
        case siteId = "site_id"
    }

    init(id: Int? = nil, device: Int? = nil, stationId: String, siteId: String?, direction: PushDirection, threshold: Double, enabled: Bool) {
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
        // Older rows or a changed column type may hold a number.
        if let text = try? values.decode(String.self, forKey: .stationId) {
            stationId = text
        } else {
            stationId = String(try values.decode(Int.self, forKey: .stationId))
        }
        siteId = try values.decodeIfPresent(String.self, forKey: .siteId)
        metric = try values.decodeIfPresent(String.self, forKey: .metric) ?? "aqi"
        direction = try values.decode(PushDirection.self, forKey: .direction)
        threshold = try values.decode(Double.self, forKey: .threshold)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    }
}

enum PushError: Error, Equatable {
    /// The Directus URL or token is missing from the build's xcconfig.
    case notConfigured
    case notAuthorized
    case noDeviceToken
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
            make(
                baseURL: getEnv("DirectusUrl"),
                token: [getEnv("DirectusPushToken"), getEnv("DirectusFeedbackToken")]
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

    /// Creates or updates the row for this token and returns its id. A token
    /// is unique, so it is looked up first. When APNs has rotated the token,
    /// `knownId` (this install's row) is moved to the new one, keeping its
    /// alerts. A lost race to create falls back to the row the other request made.
    static func upsertDevice(_ payload: PushDevicePayload, knownId: Int? = nil, config: Config, session: URLSession = .shared) async throws -> Int {
        let update = { (id: Int) in
            try await send(makeRequest(config: config, method: "PATCH", path: "\(devicesPath)/\(id)", query: [("fields", "id")], body: payload), session: session)
        }

        if let id = try await deviceId(token: payload.deviceToken, config: config, session: session) {
            _ = try await update(id)
            return id
        }

        if let id = knownId {
            do {
                _ = try await update(id)
                return id
            } catch PushError.server(let status) where [403, 404].contains(status) {
                // That row is gone or not ours to change; start a new one.
            }
        }

        do {
            let data = try await send(makeRequest(config: config, method: "POST", path: devicesPath, query: [("fields", "id")], body: payload), session: session)
            return try JSONDecoder().decode(Item<IdOnly>.self, from: data).data.id
        } catch PushError.server(let status) where status == 400 {
            if let id = try await deviceId(token: payload.deviceToken, config: config, session: session) {
                return id
            }
            throw PushError.server(statusCode: status)
        }
    }

    static func deviceId(token: String, config: Config, session: URLSession = .shared) async throws -> Int? {
        let request = makeRequest(config: config, method: "GET", path: devicesPath, query: [
            ("fields", "id"),
            ("filter[device_token][_eq]", token),
            ("limit", "1"),
        ])
        let data = try await send(request, session: session)
        return try JSONDecoder().decode(Items<IdOnly>.self, from: data).data.first?.id
    }

    // MARK: - Subscriptions

    static func subscriptions(device: Int, config: Config, session: URLSession = .shared) async throws -> [PushSubscription] {
        let request = makeRequest(config: config, method: "GET", path: subscriptionsPath, query: [
            ("fields", "id,device,station_id,site_id,metric,direction,threshold,enabled"),
            ("filter[device][_eq]", String(device)),
            ("filter[archived][_eq]", "false"),
            ("sort", "id"),
            ("limit", "-1"),
        ])
        let data = try await send(request, session: session)
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
        let data = try await send(makeRequest(config: config, method: "POST", path: subscriptionsPath, query: [("fields", "id")], body: item), session: session)
        return try JSONDecoder().decode(Item<IdOnly>.self, from: data).data.id
    }

    /// Soft-deletes: the rows stay, with `archived` set and alerts off.
    static func archive(subscriptions ids: [Int], config: Config, session: URLSession = .shared) async throws {
        guard !ids.isEmpty else { return }
        let body = BatchUpdate(keys: ids, data: ArchiveChanges())
        _ = try await send(makeRequest(config: config, method: "PATCH", path: subscriptionsPath, query: [("fields", "id")], body: body), session: session)
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
        var threshold: Double
        var enabled: Bool

        enum CodingKeys: String, CodingKey {
            case threshold, enabled
            case siteId = "site_id"
        }

        // Leaves site_id alone rather than clearing it when the cam is unknown.
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
