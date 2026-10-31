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

    private func json(_ value: Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(AnyEncodable(value))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private var taipei: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: hour, minute: minute))!
    }

    // MARK: - Direction mapping

    func testPollutionIsAboveAndCleanlinessIsBelow() {
        XCTAssertEqual(PushDirection(.pollution), .above)
        XCTAssertEqual(PushDirection(.cleanliness), .below)
    }

    func testStationAlertsFromOneSignalSetting() {
        let setting = OneSignalStationSetting(
            stationName: "Banqiao",
            isPollutionNotificationEnabled: true,
            isCleanlinessNotificationEnabled: true,
            pollutionTherhold: 150,
            cleanlinessTherhold: 25
        )
        XCTAssertEqual(StationAlerts(setting), StationAlerts(above: 150, below: 25))
    }

    func testStationAlertsOffWhenSwitchedOff() {
        let setting = OneSignalStationSetting(
            stationName: "Banqiao",
            isPollutionNotificationEnabled: false,
            isCleanlinessNotificationEnabled: true,
            pollutionTherhold: 150,
            cleanlinessTherhold: 25
        )
        let alerts = StationAlerts(setting)
        XCTAssertNil(alerts.above)
        XCTAssertEqual(alerts.below, 25)
        XCTAssertFalse(alerts.isOff)
        XCTAssertTrue(StationAlerts(OneSignalStationSetting(stationName: "x", isPollutionNotificationEnabled: false, isCleanlinessNotificationEnabled: false)).isOff)
    }

    // MARK: - Subscription encoding

    func testSubscriptionEncodesThresholdSpelledRight() throws {
        let item = PushSubscription(stationId: "12", siteId: nil, direction: .above, threshold: 120, enabled: true)
        let body = try json(item)

        XCTAssertEqual(body["threshold"] as? Int, 120)
        XCTAssertNil(body["therhold"])
        XCTAssertEqual(body["station_id"] as? String, "12")
        XCTAssertEqual(body["direction"] as? String, "above")
        XCTAssertEqual(body["metric"] as? String, "aqi")
        XCTAssertEqual(body["enabled"] as? Bool, true)
        // Unknown cam: left out, not cleared.
        XCTAssertFalse(body.keys.contains("site_id"))
        XCTAssertFalse(body.keys.contains("id"))
    }

    func testSubscriptionChangesUseThreshold() throws {
        let body = try json(PushService.SubscriptionChanges(siteId: "A12", threshold: 30, enabled: true))
        XCTAssertEqual(body["threshold"] as? Int, 30)
        XCTAssertEqual(body["site_id"] as? String, "A12")
        XCTAssertNil(body["therhold"])
    }

    func testSubscriptionDecodesNumericColumns() throws {
        let data = Data(#"{"id":3,"device":7,"station_id":42,"direction":"below","threshold":30.0,"enabled":true}"#.utf8)
        let item = try JSONDecoder().decode(PushSubscription.self, from: data)
        XCTAssertEqual(item.stationId, "42")
        XCTAssertEqual(item.threshold, 30)
        XCTAssertEqual(item.direction, .below)
    }

    func testArchiveIsSoft() throws {
        let body = try json(PushService.BatchUpdate(keys: [1, 2], data: PushService.ArchiveChanges()))
        XCTAssertEqual(body["keys"] as? [Int], [1, 2])
        let data = try XCTUnwrap(body["data"] as? [String: Any])
        XCTAssertEqual(data["archived"] as? Bool, true)
        XCTAssertEqual(data["enabled"] as? Bool, false)
    }

    // MARK: - Device encoding

    func testHourMinuteIsZeroPadded() {
        XCTAssertEqual(PushDevicePayload.hourMinute(date(7, 5, in: taipei), calendar: taipei), "07:05")
        XCTAssertEqual(PushDevicePayload.hourMinute(date(23, 0, in: taipei), calendar: taipei), "23:00")
        XCTAssertEqual(PushDevicePayload.hourMinute(date(0, 0, in: taipei), calendar: taipei), "00:00")
    }

    func testDevicePayloadEncodesDndAsHourMinute() throws {
        let payload = PushDevicePayload.make(
            deviceId: "6f1c2e7a-0000-4000-8000-000000000001",
            deviceToken: "abcd",
            externalId: "player",
            dndEnabled: true,
            dndStart: date(22, 30, in: taipei),
            dndEnd: date(7, 0, in: taipei),
            now: Date(timeIntervalSince1970: 0),
            environment: .sandbox,
            calendar: taipei
        )
        let body = try json(payload)

        XCTAssertEqual(body["device_token"] as? String, "abcd")
        XCTAssertEqual(body["environment"] as? String, "sandbox")
        // The stable device id is the upsert key.
        XCTAssertEqual(PushDevicePayload.deviceIdField, "device_id")
        XCTAssertEqual(body["device_id"] as? String, "6f1c2e7a-0000-4000-8000-000000000001")
        XCTAssertNil(body["install_id"])
        XCTAssertEqual(body["external_id"] as? String, "player")
        XCTAssertEqual(body["dnd_enabled"] as? Bool, true)
        XCTAssertEqual(body["dnd_start"] as? String, "22:30")
        XCTAssertEqual(body["dnd_end"] as? String, "07:00")
        XCTAssertEqual(body["timezone"] as? String, "Asia/Taipei")
        XCTAssertEqual(body["last_seen_at"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual(body["archived"] as? Bool, false)
    }

    func testDevicePayloadOmitsMissingExternalId() throws {
        let payload = PushDevicePayload.make(
            deviceId: "d", deviceToken: "abcd", externalId: nil, dndEnabled: false,
            dndStart: Date(), dndEnd: Date(), environment: .production, calendar: taipei
        )
        XCTAssertFalse(try json(payload).keys.contains("external_id"))
    }

    // MARK: - Reconcile plan

    func testPlanCreatesRowsForNewAlerts() {
        let plan = PushService.plan(existing: [], stationId: "5", siteId: "A1", alerts: StationAlerts(above: 120, below: 30))
        XCTAssertEqual(plan.save, [
            PushSubscription(stationId: "5", siteId: "A1", direction: .above, threshold: 120, enabled: true),
            PushSubscription(stationId: "5", siteId: "A1", direction: .below, threshold: 30, enabled: true),
        ])
        XCTAssertEqual(plan.archive, [])
    }

    func testPlanUpdatesChangedThresholdAndArchivesSwitchedOff() {
        let existing = [
            PushSubscription(id: 1, stationId: "5", siteId: nil, direction: .above, threshold: 100, enabled: true),
            PushSubscription(id: 2, stationId: "5", siteId: nil, direction: .below, threshold: 30, enabled: true),
        ]
        let plan = PushService.plan(existing: existing, stationId: "5", siteId: nil, alerts: StationAlerts(above: 150))
        XCTAssertEqual(plan.save, [PushSubscription(id: 1, stationId: "5", siteId: nil, direction: .above, threshold: 150, enabled: true)])
        XCTAssertEqual(plan.archive, [2])
    }

    func testPlanLeavesMatchingRowsAndArchivesDuplicates() {
        let existing = [
            PushSubscription(id: 1, stationId: "5", siteId: nil, direction: .above, threshold: 120, enabled: true),
            PushSubscription(id: 4, stationId: "5", siteId: nil, direction: .above, threshold: 90, enabled: true),
        ]
        let plan = PushService.plan(existing: existing, stationId: "5", siteId: nil, alerts: StationAlerts(above: 120))
        XCTAssertEqual(plan.save, [])
        XCTAssertEqual(plan.archive, [4])
    }

    func testPlanArchivesEverythingWhenOff() {
        let existing = [
            PushSubscription(id: 1, stationId: "5", siteId: nil, direction: .above, threshold: 120, enabled: true),
            PushSubscription(id: 2, stationId: "5", siteId: nil, direction: .below, threshold: 30, enabled: true),
        ]
        let plan = PushService.plan(existing: existing, stationId: "5", siteId: nil, alerts: .off)
        XCTAssertEqual(plan.save, [])
        XCTAssertEqual(plan.archive, [1, 2])
    }

    // MARK: - Config

    func testConfigPrefersPushTokenThenFeedbackToken() {
        XCTAssertEqual(PushService.Config.make(baseURL: "https://cms.example", pushToken: "push", feedbackToken: "fb")?.token, "push")
        XCTAssertEqual(PushService.Config.make(baseURL: "https://cms.example", pushToken: " ", feedbackToken: "fb")?.token, "fb")
        XCTAssertEqual(PushService.Config.make(baseURL: "https://cms.example", pushToken: nil, feedbackToken: "fb")?.token, "fb")
        XCTAssertNil(PushService.Config.make(baseURL: "https://cms.example", pushToken: "", feedbackToken: ""))
        XCTAssertNil(PushService.Config.make(baseURL: "", pushToken: "push", feedbackToken: nil))
    }

    func testRequestCarriesBearerToken() {
        let config = PushService.Config(baseURL: URL(string: "https://cms.example")!, token: "secret")
        let request = PushService.makeRequest(config: config, method: "GET", path: PushService.subscriptionsPath, query: [("filter[archived][_eq]", "false")])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(request.url?.path, "/items/twaqi_push_subscriptions")
        XCTAssertEqual(request.url?.query?.removingPercentEncoding, "filter[archived][_eq]=false")
    }
}

/// Lets the tests encode an existential.
private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
