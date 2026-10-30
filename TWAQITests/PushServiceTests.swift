//
//  PushServiceTests.swift
//  TWAQITests
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class PushServiceTests: XCTestCase {

    private let config = PushService.Config(baseURL: URL(string: "https://cms.example.com")!, token: "test-token")

    private var taipei: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }

    private func time(_ hour: Int, _ minute: Int) -> Date {
        taipei.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: hour, minute: minute))!
    }

    private func json(_ value: Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func device() -> PushDevicePayload {
        PushDevicePayload.make(
            deviceToken: "abc123",
            installId: "install-1",
            dndEnabled: true,
            dndStart: time(23, 0),
            dndEnd: time(7, 5),
            now: Date(timeIntervalSince1970: 0),
            environment: .sandbox,
            calendar: taipei
        )
    }

    // MARK: - Device

    func testDeviceEncodesDirectusFieldNames() throws {
        let object = try json(device())

        XCTAssertEqual(Set(object.keys), [
            "device_token", "environment", "app_version", "locale", "last_seen_at", "install_id",
            "dnd_enabled", "dnd_start", "dnd_end", "timezone", "archived",
        ])
        XCTAssertEqual(object["device_token"] as? String, "abc123")
        XCTAssertEqual(object["environment"] as? String, "sandbox")
        XCTAssertEqual(object["last_seen_at"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual(object["archived"] as? Bool, false)
    }

    func testDeviceSendsQuietHoursAsWallClockTimes() {
        let made = device()

        XCTAssertEqual(made.dndStart, "23:00")
        XCTAssertEqual(made.dndEnd, "07:05")
        XCTAssertEqual(made.timezone, "Asia/Taipei")
        XCTAssertTrue(made.dndEnabled)
    }

    func testDeviceNeverSendsWorkerFields() throws {
        let object = try json(device())

        XCTAssertNil(object["external_id"])
        XCTAssertNil(object["id"])
    }

    func testHexToken() {
        XCTAssertEqual(PushDevicePayload.hexToken(Data([0x00, 0xAB, 0x0F, 0xFF])), "00ab0fff")
    }

    // MARK: - Environment

    private func profile(aps: String?) -> Data {
        var entitlements: [String: Any] = ["application-identifier": "CC4C8V8BXN.com.kfpun.twaqi"]
        entitlements["aps-environment"] = aps
        let plist = try! PropertyListSerialization.data(
            fromPropertyList: ["Name": "TWAQI", "Entitlements": entitlements],
            format: .xml,
            options: 0
        )
        // The real file wraps the plist in a CMS signature.
        return Data([0x30, 0x80, 0x06, 0x09]) + plist + Data([0x00, 0x00, 0xA0])
    }

    func testEnvironmentFromProvisioningProfile() {
        XCTAssertEqual(PushEnvironment.from(provisioningProfile: profile(aps: "development")), .sandbox)
        XCTAssertEqual(PushEnvironment.from(provisioningProfile: profile(aps: "production")), .production)
    }

    func testEnvironmentWithoutProfileIsProduction() {
        // App Store and TestFlight builds ship without embedded.mobileprovision.
        XCTAssertEqual(PushEnvironment.from(provisioningProfile: nil), .production)
        XCTAssertEqual(PushEnvironment.from(provisioningProfile: Data("junk".utf8)), .production)
        XCTAssertEqual(PushEnvironment.from(provisioningProfile: profile(aps: nil)), .production)
    }

    // MARK: - Subscription

    func testNewSubscriptionEncodesForCreate() throws {
        var subscription = PushSubscription(stationId: "91", siteId: "001", direction: .above, threshold: 100, enabled: true)
        subscription.device = 7
        let object = try json(subscription)

        XCTAssertEqual(Set(object.keys), ["device", "station_id", "site_id", "metric", "direction", "threshold", "enabled"])
        XCTAssertEqual(object["station_id"] as? String, "91")
        XCTAssertEqual(object["metric"] as? String, "aqi")
        XCTAssertEqual(object["direction"] as? String, "above")
        // Worker state is never written by the app.
        XCTAssertNil(object["in_zone"])
        XCTAssertNil(object["last_fired_at"])
    }

    func testSubscriptionDecodesStringOrNumberStationId() throws {
        let data = Data("""
        {"data": [
          {"id": 1, "device": 7, "station_id": "91", "site_id": null, "metric": "aqi", "direction": "below", "threshold": 30.5, "enabled": true},
          {"id": 2, "device": 7, "station_id": 92, "direction": "above", "threshold": 100, "enabled": false}
        ]}
        """.utf8)
        struct Items: Decodable { let data: [PushSubscription] }
        let items = try JSONDecoder().decode(Items.self, from: data).data

        XCTAssertEqual(items.map(\.stationId), ["91", "92"])
        XCTAssertEqual(items[0].direction, .below)
        XCTAssertEqual(items[0].threshold, 30.5)
        XCTAssertNil(items[0].siteId)
        XCTAssertFalse(items[1].enabled)
    }

    func testChangesLeaveUnknownSiteIdAlone() throws {
        let object = try json(PushService.SubscriptionChanges(siteId: nil, threshold: 80, enabled: false))
        XCTAssertEqual(Set(object.keys), ["threshold", "enabled"])
    }

    func testArchiveIsASoftDelete() throws {
        let object = try json(PushService.BatchUpdate(keys: [1, 2], data: PushService.ArchiveChanges()))
        XCTAssertEqual(object["keys"] as? [Int], [1, 2])
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["archived"] as? Bool, true)
        XCTAssertEqual(data["enabled"] as? Bool, false)
    }

    // MARK: - Requests

    func testDeviceLookupFiltersByToken() throws {
        let request = PushService.makeRequest(config: config, method: "GET", path: PushService.devicesPath, query: [
            ("fields", "id"),
            ("filter[device_token][_eq]", "abc123"),
        ])
        let url = try XCTUnwrap(request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        XCTAssertEqual(url.path, "/items/twaqi_push_devices")
        XCTAssertTrue(items.contains(URLQueryItem(name: "filter[device_token][_eq]", value: "abc123")))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertNil(request.httpBody)
    }

    func testWriteRequestCarriesJsonBody() throws {
        let request = PushService.makeRequest(config: config, method: "PATCH", path: "\(PushService.devicesPath)/3", body: device())

        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/items/twaqi_push_devices/3")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["device_token"] as? String, "abc123")
    }

    func testConfigNeedsUrlAndToken() {
        XCTAssertNotNil(PushService.Config.make(baseURL: "https://cms.example.com", token: "t"))
        XCTAssertNil(PushService.Config.make(baseURL: "https://cms.example.com", token: " "))
        XCTAssertNil(PushService.Config.make(baseURL: "", token: "t"))
        XCTAssertNil(PushService.Config.make(baseURL: nil, token: nil))
    }

    // MARK: - Tap

    func testStationIdFromPayload() {
        XCTAssertEqual(PushManager.stationId(from: ["station_id": 91]), 91)
        XCTAssertEqual(PushManager.stationId(from: ["station_id": NSNumber(value: 92)]), 92)
        XCTAssertEqual(PushManager.stationId(from: ["station_id": "93"]), 93)
        XCTAssertNil(PushManager.stationId(from: ["station_id": NSNull()]))
        XCTAssertNil(PushManager.stationId(from: [:]))
    }
}
