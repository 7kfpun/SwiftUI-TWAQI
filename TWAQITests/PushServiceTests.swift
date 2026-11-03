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

    func testStationAlertsFromSetting() {
        let setting = StationAlertSetting(
            isPollutionNotificationEnabled: true,
            isCleanlinessNotificationEnabled: true,
            pollutionTherhold: 150,
            cleanlinessTherhold: 25
        )
        XCTAssertEqual(StationAlerts(setting), StationAlerts(above: 150, below: 25))
    }

    func testStationAlertsOffWhenSwitchedOff() {
        let setting = StationAlertSetting(
            isPollutionNotificationEnabled: false,
            isCleanlinessNotificationEnabled: true,
            pollutionTherhold: 150,
            cleanlinessTherhold: 25
        )
        let alerts = StationAlerts(setting)
        XCTAssertNil(alerts.above)
        XCTAssertEqual(alerts.below, 25)
        XCTAssertFalse(alerts.isOff)
        XCTAssertTrue(StationAlerts(StationAlertSetting.off).isOff)
    }

    func testSettingRoundTripsThroughAlerts() {
        let alerts = StationAlerts(above: 150, below: nil)
        let setting = StationAlertSetting(alerts)
        XCTAssertTrue(setting.isPollutionNotificationEnabled)
        XCTAssertFalse(setting.isCleanlinessNotificationEnabled)
        XCTAssertEqual(setting.pollutionTherhold, 150)
        // An alert that's off keeps its slider's default.
        XCTAssertEqual(setting.cleanlinessTherhold, 30)
        XCTAssertEqual(StationAlerts(setting), alerts)
    }

    func testAlertsByStationTakesFirstLiveRowPerDirection() {
        let rows = [
            PushSubscription(id: 1, stationId: "5", siteId: nil, direction: .above, threshold: 120, enabled: true),
            PushSubscription(id: 2, stationId: "5", siteId: nil, direction: .above, threshold: 200, enabled: true),
            PushSubscription(id: 3, stationId: "5", siteId: nil, direction: .below, threshold: 30, enabled: false),
            PushSubscription(id: 4, stationId: "9", siteId: nil, direction: .below, threshold: 25, enabled: true),
            PushSubscription(id: 5, stationId: "7", siteId: nil, direction: .below, threshold: 25, enabled: false),
        ]
        XCTAssertEqual(StationAlerts.byStation(rows), [
            "5": StationAlerts(above: 120),
            "9": StationAlerts(below: 25),
        ])
    }

    func testStoredDeviceDecodesAndParsesTimes() throws {
        let data = Data(#"{"id":7,"dnd_enabled":true,"dnd_start":"22:30:00","dnd_end":"07:05"}"#.utf8)
        let device = try JSONDecoder().decode(PushService.StoredDevice.self, from: data)
        XCTAssertEqual(device.id, 7)
        XCTAssertEqual(device.dndEnabled, true)

        let now = date(12, 0, in: taipei)
        let start = try XCTUnwrap(PushService.StoredDevice.time(device.dndStart, calendar: taipei, now: now))
        let end = try XCTUnwrap(PushService.StoredDevice.time(device.dndEnd, calendar: taipei, now: now))
        XCTAssertEqual(PushDevicePayload.hourMinute(start, calendar: taipei), "22:30")
        XCTAssertEqual(PushDevicePayload.hourMinute(end, calendar: taipei), "07:05")
        XCTAssertNil(PushService.StoredDevice.time(nil))
        XCTAssertNil(PushService.StoredDevice.time("25:00"))
        XCTAssertNil(PushService.StoredDevice.time("noon"))
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

    func testStationChangeSendsOffAsNull() throws {
        let body = try json(PushService.StationChange(siteId: "A12", above: 120, below: nil))
        XCTAssertEqual(body["above"] as? Int, 120)
        XCTAssertEqual(body["site_id"] as? String, "A12")
        // Off is an explicit null, not a missing key.
        XCTAssertTrue(body.keys.contains("below"))
        XCTAssertTrue(body["below"] is NSNull)
        // Unknown cam: left out.
        XCTAssertFalse(try json(PushService.StationChange(siteId: nil, above: nil, below: 30)).keys.contains("site_id"))
    }

    func testSubscriptionDecodesNumericColumns() throws {
        let data = Data(#"{"id":3,"device":7,"station_id":42,"direction":"below","threshold":30.0,"enabled":true}"#.utf8)
        let item = try JSONDecoder().decode(PushSubscription.self, from: data)
        XCTAssertEqual(item.stationId, "42")
        XCTAssertEqual(item.threshold, 30)
        XCTAssertEqual(item.direction, .below)
    }

    func testRestoreDecodesDeviceAndAlerts() throws {
        let data = Data(#"{"device":{"id":5,"dnd_enabled":true,"dnd_start":"22:00","dnd_end":"07:00"},"subscriptions":[{"id":7,"station_id":"105","site_id":"015","metric":"aqi","direction":"above","threshold":120,"enabled":true}]}"#.utf8)
        let restored = try JSONDecoder().decode(PushService.Restored.self, from: data)
        XCTAssertEqual(restored.device?.id, 5)
        XCTAssertEqual(StationAlerts.byStation(restored.subscriptions), ["105": StationAlerts(above: 120)])
        let none = try JSONDecoder().decode(PushService.Restored.self, from: Data(#"{"device":null,"subscriptions":[]}"#.utf8))
        XCTAssertNil(none.device)
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
            fcmToken: "fcm:abc",
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
        XCTAssertEqual(body["fcm_token"] as? String, "fcm:abc")
        // OneSignal's player id is no longer written; the column is left as is.
        XCTAssertFalse(body.keys.contains("external_id"))
        XCTAssertEqual(body["dnd_enabled"] as? Bool, true)
        XCTAssertEqual(body["dnd_start"] as? String, "22:30")
        XCTAssertEqual(body["dnd_end"] as? String, "07:00")
        XCTAssertEqual(body["timezone"] as? String, "Asia/Taipei")
        XCTAssertEqual(body["last_seen_at"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual(body["archived"] as? Bool, false)
        XCTAssertEqual(body["is_pro"] as? Bool, false)
    }

    func testDevicePayloadCarriesProAndHelpLanguage() throws {
        func payload(isPro: Bool, language: AppLanguage) -> PushDevicePayload {
            PushDevicePayload.make(
                deviceId: "d", deviceToken: "abcd", fcmToken: "f", dndEnabled: false,
                dndStart: Date(), dndEnd: Date(), isPro: isPro, language: language,
                environment: .production, calendar: taipei
            )
        }
        let chinese = try json(payload(isPro: true, language: .traditionalChinese))
        XCTAssertEqual(chinese["is_pro"] as? Bool, true)
        // Help's choice, not the language iOS picked for the app.
        XCTAssertEqual(chinese["locale"] as? String, "zh-Hant")
        XCTAssertEqual(try json(payload(isPro: false, language: .english))["locale"] as? String, "en")
        // "Follow the system" falls back to what iOS gives the app.
        XCTAssertEqual(payload(isPro: false, language: .system).locale, Bundle.main.preferredLocalizations.first)

        // Either one changing changes the profile the mirror compares.
        XCTAssertTrue(payload(isPro: true, language: .traditionalChinese).profile.hasPrefix("zh-Hant|true|"))
        XCTAssertNotEqual(payload(isPro: true, language: .english).profile, payload(isPro: false, language: .english).profile)
    }

    func testDevicePayloadOmitsMissingFcmToken() throws {
        let payload = PushDevicePayload.make(
            deviceId: "d", deviceToken: "abcd", fcmToken: nil, dndEnabled: false,
            dndStart: Date(), dndEnd: Date(), environment: .production, calendar: taipei
        )
        let body = try json(payload)
        // Left out, not cleared: a row keeps its last FCM token until a new one.
        XCTAssertFalse(body.keys.contains("fcm_token"))
        XCTAssertFalse(body.keys.contains("external_id"))
    }

    // MARK: - Device sync gate

    func testDeviceWithNoPendingAlertsStillSyncs() {
        // An FCM token refresh arrives with no station changes pending.
        XCTAssertTrue(DirectusPushMirror.needsDevice(hasDevice: true, pending: [:]))
        // No row yet: only an alert being switched on makes one.
        XCTAssertFalse(DirectusPushMirror.needsDevice(hasDevice: false, pending: [:]))
        XCTAssertFalse(DirectusPushMirror.needsDevice(hasDevice: false, pending: ["5": .off]))
        XCTAssertTrue(DirectusPushMirror.needsDevice(hasDevice: false, pending: ["5": StationAlerts(above: 120)]))
    }

    func testNewFcmTokenAloneForcesUpsert() {
        let now = Date()
        let recent = now.addingTimeInterval(-60)
        func current(token: String = "apns", fcm: String? = "fcm-1", lastSync: Date? = recent) -> Bool {
            DirectusPushMirror.isDeviceCurrent(
                syncedToken: "apns", token: token,
                syncedFcmToken: "fcm-1", fcmToken: fcm, lastSync: lastSync, now: now
            )
        }
        XCTAssertTrue(current())
        // Same APNs token, refreshed recently, but FCM rotated: write it.
        XCTAssertFalse(current(fcm: "fcm-2"))
        // Messaging hasn't issued a token yet: not a change.
        XCTAssertTrue(current(fcm: nil))
        XCTAssertFalse(current(token: "apns-new"))
        XCTAssertFalse(current(lastSync: nil))
        XCTAssertFalse(current(lastSync: now.addingTimeInterval(-DirectusPushMirror.deviceRefreshInterval - 1)))
    }

    func testNewLanguageOrProForcesUpsert() {
        let now = Date()
        func current(synced: String?, profile: String?) -> Bool {
            DirectusPushMirror.isDeviceCurrent(
                syncedToken: "apns", token: "apns",
                syncedFcmToken: "fcm", fcmToken: "fcm", lastSync: now.addingTimeInterval(-60),
                syncedProfile: synced, profile: profile, now: now
            )
        }
        XCTAssertTrue(current(synced: "en|false", profile: "en|false"))
        // Language changed under Help, or Pro started or lapsed: write it.
        XCTAssertFalse(current(synced: "en|false", profile: "zh-Hant|false"))
        XCTAssertFalse(current(synced: "en|false", profile: "en|true"))
        // A row written before the profile was tracked is rewritten once.
        XCTAssertFalse(current(synced: nil, profile: "en|false"))
    }

    func testDndChangeStaysPendingUntilWritten() {
        // The DND window is in the profile, which is saved only after a write
        // succeeds: a failed write leaves the old profile, so the next flush,
        // even after a relaunch, still sees a change (review: no lost DND).
        func payload(dnd: Bool, start: Date) -> PushDevicePayload {
            PushDevicePayload.make(
                deviceId: "d", deviceToken: "abcd", fcmToken: "f", dndEnabled: dnd,
                dndStart: start, dndEnd: date(7, 0, in: taipei), environment: .production, calendar: taipei
            )
        }
        let before = payload(dnd: false, start: date(22, 0, in: taipei)).profile
        XCTAssertNotEqual(payload(dnd: true, start: date(22, 0, in: taipei)).profile, before)
        XCTAssertNotEqual(payload(dnd: false, start: date(23, 30, in: taipei)).profile, before)
        XCTAssertFalse(DirectusPushMirror.isDeviceCurrent(
            syncedToken: "apns", token: "apns", syncedFcmToken: "f", fcmToken: "f",
            lastSync: Date(), syncedProfile: before, profile: payload(dnd: true, start: date(22, 0, in: taipei)).profile
        ))
    }

    // MARK: - Config

    func testConfigNeedsAnHttpsPushApi() {
        XCTAssertEqual(PushService.Config.make(baseURL: "https://push.example", deviceId: "d", secret: "s")?.baseURL.host, "push.example")
        XCTAssertNil(PushService.Config.make(baseURL: "", deviceId: "d", secret: "s"))
        XCTAssertNil(PushService.Config.make(baseURL: nil, deviceId: "d", secret: "s"))
        XCTAssertNil(PushService.Config.make(baseURL: "http://push.example", deviceId: "d", secret: "s"))
    }

    func testRequestSignsWithTheDeviceNotADirectusToken() {
        let config = PushService.Config(baseURL: URL(string: "https://push.example")!, deviceId: "6f1c2e7a-0000-4000-8000-000000000001", secret: "s3cret")
        let request = PushService.makeRequest(config: config, method: "PUT", path: "app/v1/stations/105", body: PushService.StationChange(siteId: nil, above: 100, below: nil))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Device-Id"), "6f1c2e7a-0000-4000-8000-000000000001")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret")
        XCTAssertEqual(request.url?.absoluteString, "https://push.example/app/v1/stations/105")
        XCTAssertEqual(request.httpMethod, "PUT")
        let restore = PushService.makeRequest(config: config, method: "GET", path: "app/v1/device", query: [("device_token", "abcd")])
        XCTAssertEqual(restore.url?.query, "device_token=abcd")
    }

    // MARK: - OneSignal tags (kept alongside FCM)

    func testOneSignalTagsMirrorAlertsAndDnd() {
        let tags = OneSignalTags.tags(
            wanted: ["105": StationAlerts(above: 120, below: 30), "126": StationAlerts(above: 90)],
            dndEnabled: true, dndStart: date(22, 30, in: taipei), dndEnd: date(7, 0, in: taipei), calendar: taipei
        )
        XCTAssertEqual(tags, [
            "105_pollution_therhold": "120",
            "105_cleanliness_therhold": "30",
            "126_pollution_therhold": "90",
            "isDndEnabled": "true",
            "dndStartTime": "1350",
            "dndEndTime": "420",
            "isDndStartEarlierThanEnd": "true",
        ])
        // DND off: its tags aren't wanted.
        XCTAssertEqual(OneSignalTags.tags(wanted: [:], dndEnabled: false, dndStart: Date(), dndEnd: Date()), [:])
    }

    func testOneSignalTagChangesSendOnlyDifferencesAndDeleteTheRest() {
        let written = ["105_pollution_therhold": "120", "126_pollution_therhold": "90", "isDndEnabled": "true"]
        let desired = ["105_pollution_therhold": "150", "126_pollution_therhold": "90"]
        XCTAssertEqual(OneSignalTags.changes(desired: desired, written: written), [
            "105_pollution_therhold": "150",
            "isDndEnabled": "",
        ])
        // Nothing new: nothing to send.
        XCTAssertEqual(OneSignalTags.changes(desired: desired, written: desired), [:])
        // An earlier build's name-keyed tag found on OneSignal is cleared.
        XCTAssertEqual(
            OneSignalTags.changes(desired: desired, written: desired, stale: ["Zhongshan_pollution_therhold", "105_pollution_therhold"]),
            ["Zhongshan_pollution_therhold": ""]
        )
        XCTAssertTrue(OneSignalTags.isStationTag("Zhongshan_cleanliness_therhold"))
        XCTAssertFalse(OneSignalTags.isStationTag("isDndEnabled"))
    }

    func testRecoveryFromThePushApi() {
        // Another install holds this id: new Keychain identity, new row.
        XCTAssertEqual(DirectusPushMirror.recovery(for: PushError.server(statusCode: 403)), .newIdentity)
        // Row retired by a newer registration of this phone: register again.
        XCTAssertEqual(DirectusPushMirror.recovery(for: PushError.server(statusCode: 404)), .register)
        // Anything else is retried as it is.
        XCTAssertEqual(DirectusPushMirror.recovery(for: PushError.server(statusCode: 502)), .none)
        XCTAssertEqual(DirectusPushMirror.recovery(for: PushError.offline), .none)
    }

    func testDeviceRowCarriesWhetherNotificationsAreAllowed() throws {
        XCTAssertEqual(PushDevicePayload.notificationsAllowed(.authorized), true)
        XCTAssertEqual(PushDevicePayload.notificationsAllowed(.provisional), true)
        XCTAssertEqual(PushDevicePayload.notificationsAllowed(.denied), false)
        // Not asked yet is unknown, not "no": onboarding writes the row before
        // it asks (Grok review), and an empty field is still sent to.
        XCTAssertNil(PushDevicePayload.notificationsAllowed(.notDetermined))

        func payload(_ allowed: Bool?) -> PushDevicePayload {
            PushDevicePayload.make(
                deviceId: "d", deviceToken: "abcd", fcmToken: "f", dndEnabled: false,
                dndStart: Date(), dndEnd: Date(), notificationsAllowed: allowed,
                environment: .production, calendar: taipei
            )
        }
        XCTAssertEqual(try json(payload(false))["notifications_allowed"] as? Bool, false)
        XCTAssertFalse(try json(payload(nil)).keys.contains("notifications_allowed"))
        // Turning notifications off (or back on) rewrites the row.
        XCTAssertNotEqual(payload(true).profile, payload(false).profile)
    }

    func testDeviceSecretIsBase64url() {
        XCTAssertEqual(PushDeviceIdentity.base64url(Data([0xfb, 0xff, 0xfe])), "-__-")
        XCTAssertEqual(PushDeviceIdentity.base64url(Data(repeating: 0, count: 32)).count, 43)
    }
}

/// Lets the tests encode an existential.
private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

/// FOX-20/31: keeping alerts and Favourites together.
final class FavouriteAlertsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "FavouriteAlertsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// An in-memory alert store that records each write.
    private final class FakeServices {
        var denied = false
        var alerted: [Int: StationAlerts] = [:]
        var writes: [(stationId: Int, alerts: StationAlerts, settled: Bool)] = []
        var cancelledAll = 0

        var services: FavouriteAlerts.Services {
            FavouriteAlerts.Services(
                notificationsDenied: { [unowned self] completion in completion(self.denied) },
                alertedStations: { [unowned self] in self.alerted },
                write: { [unowned self] stationId, _, alerts, settled in
                    self.writes.append((stationId, alerts, settled))
                    self.alerted[stationId] = alerts.isOff ? nil : alerts
                },
                cancelAll: { [unowned self] in
                    self.cancelledAll += 1
                    self.alerted = [:]
                }
            )
        }
    }

    /// The `changed` notifications posted while `work` runs, as station → on.
    private func posts(_ work: () -> Void) -> [(Int, Bool)] {
        var seen: [(Int, Bool)] = []
        let observer = NotificationCenter.default.addObserver(forName: FavouriteAlerts.changed, object: nil, queue: nil) { note in
            if let id = note.userInfo?[FavouriteAlerts.stationIdKey] as? Int,
               let isOn = note.userInfo?[FavouriteAlerts.isOnKey] as? Bool {
                seen.append((id, isOn))
            }
        }
        work()
        NotificationCenter.default.removeObserver(observer)
        return seen
    }

    private func enable(_ stationId: Int, _ fake: FakeServices, isStillFavourite: Bool = true) -> FavouriteAlerts.NewFavouriteOutcome? {
        let done = expectation(description: "enabled")
        var outcome: FavouriteAlerts.NewFavouriteOutcome?
        FavouriteAlerts.enableForNewFavourite(
            stationId: stationId,
            siteId: nil,
            isStillFavourite: { isStillFavourite },
            services: fake.services
        ) {
            outcome = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        return outcome
    }

    func testStoredAlertsReadOnlyStationsWithAnAlertOn() throws {
        let wanted: [String: StationAlerts] = ["126": StationAlerts(above: 150), "7": .off, "x": StationAlerts(below: 20)]
        defaults.set(try JSONEncoder().encode(wanted), forKey: "directusPushWantedAlerts")

        XCTAssertEqual(DirectusPushMirror.alertedStations(defaults: defaults), [126: StationAlerts(above: 150)])
        XCTAssertEqual(DirectusPushMirror.alerts(stationId: 126, defaults: defaults), StationAlerts(above: 150))
        XCTAssertEqual(DirectusPushMirror.alerts(stationId: 7, defaults: defaults), .off)
        XCTAssertEqual(DirectusPushMirror.alerts(stationId: 8, defaults: defaults), .off)
    }

    func testChangedNotificationIsReadForItsStationOnly() {
        let notification = Notification(name: FavouriteAlerts.changed, userInfo: [
            FavouriteAlerts.stationIdKey: 126,
            FavouriteAlerts.isOnKey: false,
        ])
        XCTAssertEqual(FavouriteAlerts.isOn(in: notification, stationId: 126), false)
        XCTAssertNil(FavouriteAlerts.isOn(in: notification, stationId: 7))
    }

    func testCapIsThreeAndCountsOtherStationsOnly() {
        XCTAssertEqual(FavouriteAlerts.maxAlertedStations, 3)
        XCTAssertFalse(FavouriteAlerts.isAtCap(alertedStationIds: [1, 3], excluding: 2))
        XCTAssertTrue(FavouriteAlerts.isAtCap(alertedStationIds: [1, 3, 4], excluding: 2))
        // Its own alerts don't count against it.
        XCTAssertFalse(FavouriteAlerts.isAtCap(alertedStationIds: [1, 2, 3], excluding: 2))
    }

    // MARK: FOX-31 — favouriting switches alerts on

    func testDefaultAlertsAreTheStationScreensFirstAboveAlert() {
        XCTAssertEqual(StationAlerts(FavouriteAlerts.defaultAlerts), StationAlerts(above: 120))
    }

    func testNewFavouriteDecision() {
        XCTAssertEqual(FavouriteAlerts.newFavouriteDecision(alertedStationIds: [1], stationId: 2), .enabled(FavouriteAlerts.defaultAlerts))
        XCTAssertEqual(FavouriteAlerts.newFavouriteDecision(alertedStationIds: [1, 3], stationId: 2), .enabled(FavouriteAlerts.defaultAlerts))
        XCTAssertEqual(FavouriteAlerts.newFavouriteDecision(alertedStationIds: [1, 3, 4], stationId: 2), .capReached)
        XCTAssertEqual(FavouriteAlerts.newFavouriteDecision(alertedStationIds: [1, 2, 3], stationId: 2), .alreadyOn)
    }

    func testEnablingWritesAndTellsTheStationScreen() {
        let fake = FakeServices()
        fake.alerted = [1: StationAlerts(below: 20)]
        var setting: StationAlertSetting?
        var count: Int?
        let observer = NotificationCenter.default.addObserver(forName: FavouriteAlerts.changed, object: nil, queue: nil) { note in
            setting = FavouriteAlerts.setting(in: note)
            count = FavouriteAlerts.alertedStationCount(in: note)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertEqual(enable(126, fake), .enabled(FavouriteAlerts.defaultAlerts))
        XCTAssertEqual(fake.writes.map(\.stationId), [126])
        XCTAssertEqual(fake.writes.first?.alerts, StationAlerts(above: 120))
        XCTAssertEqual(fake.writes.first?.settled, true)
        XCTAssertEqual(setting, FavouriteAlerts.defaultAlerts)
        XCTAssertEqual(count, 2)
    }

    func testAlreadyOnKeepsItsThresholds() {
        let fake = FakeServices()
        fake.alerted = [126: StationAlerts(above: 90)]
        XCTAssertEqual(enable(126, fake), .alreadyOn)
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertEqual(fake.alerted[126], StationAlerts(above: 90))
    }

    func testCapReachedWritesNothing() {
        let fake = FakeServices()
        fake.alerted = [1: StationAlerts(above: 100), 3: StationAlerts(above: 100), 4: StationAlerts(below: 30)]
        XCTAssertEqual(enable(126, fake), .capReached)
        XCTAssertTrue(fake.writes.isEmpty)
    }

    func testNotificationsDeniedWritesNothing() {
        let fake = FakeServices()
        fake.denied = true
        XCTAssertEqual(enable(126, fake), .notificationsDenied)
        XCTAssertTrue(fake.writes.isEmpty)
    }

    func testUnfavouritedBeforeTheWriteIsLeftAlone() {
        let fake = FakeServices()
        XCTAssertEqual(enable(126, fake, isStillFavourite: false), .notChanged)
        XCTAssertTrue(fake.writes.isEmpty)
    }

    // MARK: Leaving Favourites, cancel all, the switches

    func testClearTurnsAlertsOffAndSaysSo() {
        let fake = FakeServices()
        fake.alerted = [126: StationAlerts(above: 120, below: 30)]
        let seen = posts { FavouriteAlerts.clear(stationId: 126, services: fake.services) }

        XCTAssertEqual(fake.writes.map(\.alerts), [.off])
        XCTAssertEqual(fake.writes.first?.settled, true)
        XCTAssertNil(fake.alerted[126])
        XCTAssertEqual(seen.map(\.0), [126])
        XCTAssertEqual(seen.map(\.1), [false])
    }

    func testClearWithAlertsOffWritesNothing() {
        let fake = FakeServices()
        let seen = posts { FavouriteAlerts.clear(stationId: 126, services: fake.services) }
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertTrue(seen.isEmpty)
    }

    func testCancelAllTurnsEveryStationOff() {
        let fake = FakeServices()
        fake.alerted = [126: StationAlerts(above: 120), 7: StationAlerts(below: 20)]
        let seen = posts { FavouriteAlerts.cancelAll(services: fake.services) }

        XCTAssertEqual(fake.cancelledAll, 1)
        XCTAssertTrue(fake.alerted.isEmpty)
        XCTAssertEqual(seen.map(\.0), [7, 126])
        XCTAssertTrue(seen.allSatisfy { !$0.1 })
    }

    func testSwitchWriteWaitsForTheSliderToStop() {
        let fake = FakeServices()
        let setting = StationAlertSetting(isPollutionNotificationEnabled: true, isCleanlinessNotificationEnabled: false, pollutionTherhold: 150)
        FavouriteAlerts.write(setting, stationId: 126, siteId: "12", services: fake.services)

        XCTAssertEqual(fake.writes.first?.alerts, StationAlerts(above: 150))
        XCTAssertEqual(fake.writes.first?.settled, false)
    }
}
