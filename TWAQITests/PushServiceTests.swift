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
// MARK: - Reading OneSignal's tags (FOX-36, FOX-37 M2)

extension PushServiceTests {
    func testTagsParseIntoStationsAndDnd() {
        let settings = OneSignalManager.settings(fromTags: [
            "isDndEnabled": "true",
            "dndStartTime": "1320",
            "dndEndTime": "420",
            "Songshan_pollution_therhold": "150.0",
            "Songshan_cleanliness_therhold": "25",
            "901_cleanliness_therhold": "20",
        ])
        XCTAssertEqual(settings.isDndEnabled, true)
        XCTAssertEqual(settings.dndStartTime, 1320)
        XCTAssertEqual(settings.dndEndTime, 420)
        XCTAssertEqual(settings.stationSettings.count, 2)
        XCTAssertEqual(settings.stationSettings["Songshan"].map { StationAlerts($0) }, StationAlerts(above: 150, below: 25))
        XCTAssertEqual(settings.stationSettings["901"].map { StationAlerts($0) }, StationAlerts(below: 20))
        XCTAssertEqual(settings.stationSettings["901"]?.stationName, "901")
    }

    func testNoTagsParseAsNoSettings() {
        let settings = OneSignalManager.settings(fromTags: nil)
        XCTAssertNil(settings.isDndEnabled)
        XCTAssertTrue(settings.stationSettings.isEmpty)
    }

    func testBadTagsAreSkippedAndTheRestStillRead() {
        // A non-string tag used to end the whole read without an answer, and
        // a threshold typed by hand in the dashboard crashed on `Double(_)!`.
        let settings = OneSignalManager.settings(fromTags: [
            42: "not a string key",
            "dndStartTime": 1320,
            "Banqiao_pollution_therhold": "high",
            "Banqiao_cleanliness_therhold": "",
            "_pollution_therhold": "100",
            "Songshan_pollution_therhold": "120",
        ])
        XCTAssertNil(settings.dndStartTime)
        XCTAssertNil(settings.stationSettings["Banqiao"])
        XCTAssertNil(settings.stationSettings[""])
        XCTAssertEqual(settings.stationSettings.keys.sorted(), ["Songshan"])
        XCTAssertEqual(settings.stationSettings["Songshan"].map { StationAlerts($0) }, StationAlerts(above: 120))
        // Still known as tags, so "cancel all" can remove them.
        XCTAssertEqual(settings.unreadableStationTagCodes, ["Banqiao"])
    }

    func testReadThatNeverAnswersFailsAfterTheTimeout() {
        let done = expectation(description: "answered")
        OneSignalManager.readOnce(timeout: 0.05, read: { (_: @escaping (Result<Int, OneSignalError>) -> Void) in }) { result in
            if case .success = result {
                XCTFail("A read with no answer should fail")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testReadAnswersOnceEvenWhenItAlsoTimesOut() {
        let done = expectation(description: "answered once")
        done.assertForOverFulfill = true
        var answers: [Int?] = []
        OneSignalManager.readOnce(timeout: 0.05, read: { answer in
            answer(.success(1))
            answer(.success(2))
        }) { result in
            answers.append(try? result.get())
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        // Let the timeout fire; it must not answer again.
        let settle = expectation(description: "timeout passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        XCTAssertEqual(answers, [1])
    }
}

private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

/// FOX-20: the pure parts of keeping alerts and Favourites together.
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

    private func store(_ alerts: [String: StationAlerts], key: String) throws {
        defaults.set(try JSONEncoder().encode(alerts), forKey: key)
    }

    func testTagCodeIsEnglishNameInTaiwanAndIdElsewhere() {
        XCTAssertEqual(FavouriteAlerts.tagCode(countryCode: "twn", name: "Songshan", stationId: 126), "Songshan")
        XCTAssertEqual(FavouriteAlerts.tagCode(countryCode: "tha", name: "Bangkok", stationId: 901), "901")
    }

    func testCandidateTagCodesTryNameThenIdAndSkipBlankName() {
        XCTAssertEqual(FavouriteAlerts.candidateTagCodes(name: "Songshan", stationId: 126), ["Songshan", "126"])
        XCTAssertEqual(FavouriteAlerts.candidateTagCodes(name: "", stationId: 126), ["126"])
    }

    func testKnownAlertsPrefersUnsentOverSent() throws {
        try store(["126": StationAlerts(above: 150)], key: "directusPushWantedAlerts")
        try store(["126": StationAlerts(above: 100), "7": StationAlerts(below: 20)], key: "directusPushSyncedAlerts")

        XCTAssertEqual(DirectusPushMirror.knownAlerts(stationId: 126, defaults: defaults), StationAlerts(above: 150))
        XCTAssertEqual(DirectusPushMirror.knownAlerts(stationId: 7, defaults: defaults), StationAlerts(below: 20))
        XCTAssertNil(DirectusPushMirror.knownAlerts(stationId: 8, defaults: defaults))
    }

    func testChangedNotificationIsReadForItsStationOnly() {
        let notification = Notification(name: FavouriteAlerts.changed, userInfo: [
            FavouriteAlerts.stationIdKey: 126,
            FavouriteAlerts.isOnKey: false,
        ])
        XCTAssertEqual(FavouriteAlerts.isOn(in: notification, stationId: 126), false)
        XCTAssertNil(FavouriteAlerts.isOn(in: notification, stationId: 7))
    }

    // MARK: FOX-31 — favouriting switches alerts on

    private func on(_ code: String, above: Double? = 120, below: Double? = nil) -> OneSignalStationSetting {
        OneSignalStationSetting(
            stationName: code,
            isPollutionNotificationEnabled: above != nil,
            isCleanlinessNotificationEnabled: below != nil,
            pollutionTherhold: above ?? 120,
            cleanlinessTherhold: below ?? 30
        )
    }

    private func settings(_ stations: [OneSignalStationSetting]) -> OneSignalSettings {
        OneSignalSettings(stationSettings: Dictionary(uniqueKeysWithValues: stations.map { ($0.stationName, $0) }))
    }

    func testDefaultAlertsAreTheStationScreensFirstAboveAlert() {
        let setting = FavouriteAlerts.defaultAlerts(tagCode: "Songshan")
        XCTAssertEqual(StationAlerts(setting), StationAlerts(above: 120))
        XCTAssertEqual(setting.getTags(), [
            "Songshan_pollution_therhold": "120.0",
            "Songshan_cleanliness_therhold": "",
        ])
    }

    func testNewFavouriteIsEnabledUnderTheCap() {
        XCTAssertEqual(
            FavouriteAlerts.newFavouriteDecision(settings: settings([]), tagCode: "Songshan"),
            .enabled(FavouriteAlerts.defaultAlerts(tagCode: "Songshan"))
        )
        XCTAssertEqual(
            FavouriteAlerts.newFavouriteDecision(settings: settings([on("Banqiao")]), tagCode: "Songshan"),
            .enabled(FavouriteAlerts.defaultAlerts(tagCode: "Songshan"))
        )
    }

    func testNewFavouriteAtTheCapStaysOff() {
        XCTAssertEqual(
            FavouriteAlerts.newFavouriteDecision(settings: settings([on("Banqiao"), on("901", above: nil, below: 20)]), tagCode: "Songshan"),
            .capReached
        )
    }

    func testNewFavouriteWithAlertsAlreadyOnKeepsItsThresholds() {
        // At the cap too: its own alerts count towards it, and are left alone.
        XCTAssertEqual(
            FavouriteAlerts.newFavouriteDecision(settings: settings([on("Banqiao"), on("Songshan", above: 150)]), tagCode: "Songshan"),
            .alreadyOn
        )
    }

    /// Records calls in order; answers synchronously, or holds OneSignal
    /// writes on the wire while `holdSends` is set.
    private final class FakeServices {
        var denied = false
        var read: Result<OneSignalSettings, OneSignalError> = .success(OneSignalSettings(stationSettings: [:]))
        var send: Result<Bool, OneSignalError> = .success(true)
        var holdSends = false
        var heldSends: [(Result<Bool, OneSignalError>) -> Void] = []
        var calls: [String] = []
        var sentTags: [String: String]?
        var mirrored: (stationId: Int, siteId: String?, alerts: StationAlerts)?
        var mirroredSettled: Bool?
        var sentTagWrites: [[String: String]] = []
        let defaults: UserDefaults

        init(defaults: UserDefaults) {
            self.defaults = defaults
        }

        var services: FavouriteAlerts.Services {
            FavouriteAlerts.Services(
                notificationsDenied: { [unowned self] in self.calls.append("permission"); $0(self.denied) },
                readSettings: { [unowned self] in self.calls.append("read"); $0(self.read) },
                sendTags: { [unowned self] tags, completion in
                    self.calls.append("onesignal")
                    self.sentTags = tags
                    self.sentTagWrites.append(tags)
                    if self.holdSends {
                        self.heldSends.append(completion)
                    } else {
                        completion(self.send)
                    }
                },
                mirror: { [unowned self] in
                    self.calls.append("directus")
                    self.mirrored = ($0, $1, $2)
                    self.mirroredSettled = $3
                },
                mirrorCancelAll: { [unowned self] in
                    self.calls.append("directus-cancel-all")
                },
                defaults: defaults
            )
        }
    }

    private func run(_ fake: FakeServices, isStillFavourite: Bool = true) -> FavouriteAlerts.NewFavouriteOutcome? {
        let done = expectation(description: "completion")
        var outcome: FavouriteAlerts.NewFavouriteOutcome?
        FavouriteAlerts.enableForNewFavourite(
            stationId: 126,
            tagCode: "Songshan",
            siteId: "012",
            isStillFavourite: { isStillFavourite },
            services: fake.services
        ) {
            XCTAssertTrue(Thread.isMainThread)
            outcome = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        return outcome
    }

    func testEnablingWritesOneSignalThenDirectusAndTellsTheStationScreen() {
        let fake = FakeServices(defaults: defaults)
        fake.read = .success(settings([on("Banqiao")]))
        let posted = expectation(forNotification: FavouriteAlerts.changed, object: nil) { notification in
            FavouriteAlerts.isOn(in: notification, stationId: 126) == true
                && FavouriteAlerts.setting(in: notification) == FavouriteAlerts.defaultAlerts(tagCode: "Songshan")
                && FavouriteAlerts.alertedStationCount(in: notification) == 2
        }

        XCTAssertEqual(run(fake), .enabled(FavouriteAlerts.defaultAlerts(tagCode: "Songshan")))
        wait(for: [posted], timeout: 2)
        XCTAssertEqual(fake.calls, ["permission", "read", "onesignal", "directus"])
        XCTAssertEqual(fake.sentTags, FavouriteAlerts.defaultAlerts(tagCode: "Songshan").getTags())
        XCTAssertEqual(fake.mirrored?.stationId, 126)
        XCTAssertEqual(fake.mirrored?.siteId, "012")
        XCTAssertEqual(fake.mirrored?.alerts, StationAlerts(above: 120))
    }

    func testCapReachedWritesNothing() {
        let fake = FakeServices(defaults: defaults)
        fake.read = .success(settings([on("Banqiao"), on("Zhongshan")]))
        XCTAssertEqual(run(fake), .capReached)
        XCTAssertEqual(fake.calls, ["permission", "read"])
    }

    func testNotificationsDeniedWritesNothing() {
        let fake = FakeServices(defaults: defaults)
        fake.denied = true
        XCTAssertEqual(run(fake), .notificationsDenied)
        XCTAssertEqual(fake.calls, ["permission"])
    }

    func testOneSignalUnreadableWritesNothing() {
        let fake = FakeServices(defaults: defaults)
        fake.read = .failure(.oneSignalError)
        XCTAssertEqual(run(fake), .notChanged)
        XCTAssertEqual(fake.calls, ["permission", "read"])
    }

    func testOneSignalWriteFailureSkipsTheDirectusCopy() {
        let fake = FakeServices(defaults: defaults)
        fake.send = .failure(.oneSignalError)
        XCTAssertEqual(run(fake), .notChanged)
        XCTAssertEqual(fake.calls, ["permission", "read", "onesignal"])
        XCTAssertNil(fake.mirrored)
    }

    func testUnfavouritedBeforeTheWriteIsLeftAlone() {
        let fake = FakeServices(defaults: defaults)
        XCTAssertEqual(run(fake, isStillFavourite: false), .notChanged)
        XCTAssertEqual(fake.calls, ["permission", "read"])
    }

    /// Lets work already queued on the main thread run.
    private func drainMain() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    /// Answers the OneSignal write held longest, and stops holding new ones.
    private func answerHeldSend(_ fake: FakeServices, _ result: Result<Bool, OneSignalError> = .success(true)) {
        fake.holdSends = false
        fake.heldSends.removeFirst()(result)
    }

    func testNewFavouriteWaitsForAClearOnTheWireAndWritesAfterIt() {
        let fake = FakeServices(defaults: defaults)
        fake.holdSends = true
        FavouriteAlerts.clear(stationId: 126, tagCodes: ["Songshan"], services: fake.services)
        XCTAssertTrue(FavouriteAlerts.isClearInFlight(stationId: 126))

        let done = expectation(description: "enabled")
        var outcome: FavouriteAlerts.NewFavouriteOutcome?
        FavouriteAlerts.enableForNewFavourite(
            stationId: 126,
            tagCode: "Songshan",
            siteId: "012",
            isStillFavourite: { true },
            services: fake.services
        ) {
            outcome = $0
            done.fulfill()
        }
        drainMain()
        // Nothing read or written while the clear may still land.
        XCTAssertEqual(fake.calls, ["onesignal"])

        answerHeldSend(fake)
        wait(for: [done], timeout: 2)
        XCTAssertEqual(outcome, .enabled(FavouriteAlerts.defaultAlerts(tagCode: "Songshan")))
        // The clear lands and is copied first; the new alerts after it, so
        // OneSignal and Directus both end on.
        XCTAssertEqual(fake.calls, ["onesignal", "directus", "permission", "read", "onesignal", "directus"])
        XCTAssertEqual(fake.sentTagWrites.last, FavouriteAlerts.defaultAlerts(tagCode: "Songshan").getTags())
        XCTAssertEqual(fake.mirrored?.alerts, StationAlerts(above: 120))
        XCTAssertFalse(FavouriteAlerts.isClearInFlight(stationId: 126))
    }

    func testNewFavouriteAfterAFailedClearOnTheWireReadsItsAlertsStillOn() {
        let fake = FakeServices(defaults: defaults)
        fake.holdSends = true
        FavouriteAlerts.clear(stationId: 126, tagCodes: ["Songshan"], services: fake.services)
        let done = expectation(description: "enabled")
        var outcome: FavouriteAlerts.NewFavouriteOutcome?
        FavouriteAlerts.enableForNewFavourite(
            stationId: 126, tagCode: "Songshan", siteId: nil, isStillFavourite: { true }, services: fake.services
        ) {
            outcome = $0
            done.fulfill()
        }
        fake.read = .success(settings([on("Songshan", above: 150)]))

        answerHeldSend(fake, .failure(.oneSignalError))
        wait(for: [done], timeout: 2)
        XCTAssertEqual(outcome, .alreadyOn)
        XCTAssertEqual(fake.calls, ["onesignal", "permission", "read"])
        XCTAssertNil(fake.mirrored)
        // Favourited again, so not retried later either.
        XCTAssertNil(FavouriteAlerts.pendingClears(defaults: defaults)[126])
    }

    func testRetryLeavesAClearStillOnTheWireAlone() {
        let fake = FakeServices(defaults: defaults)
        fake.holdSends = true
        FavouriteAlerts.clear(stationId: removed, tagCodes: ["Songshan"], services: fake.services)
        FavouriteAlerts.retryPendingClears(isFavourite: { _ in false }, services: fake.services)
        XCTAssertEqual(fake.sentTagWrites.count, 1)

        answerHeldSend(fake)
        drainMain()
        XCTAssertTrue(FavouriteAlerts.pendingClears(defaults: defaults).isEmpty)
    }

    func testSwitchWriteWaitsForAClearOnTheWireAndTheScreenKeepsIt() {
        let fake = FakeServices(defaults: defaults)
        fake.holdSends = true
        FavouriteAlerts.clear(stationId: 126, tagCodes: ["Songshan"], services: fake.services)
        let saidOff = expectation(forNotification: FavouriteAlerts.changed, object: nil) { notification in
            FavouriteAlerts.isOn(in: notification, stationId: 126) == false
        }
        saidOff.isInverted = true

        let written = expectation(description: "written")
        FavouriteAlerts.write(on("Songshan", above: 150), stationId: 126, siteId: "012", isCurrent: { true }, services: fake.services) {
            XCTAssertTrue($0)
            written.fulfill()
        }
        drainMain()
        XCTAssertEqual(fake.sentTagWrites.count, 1)

        answerHeldSend(fake)
        wait(for: [written, saidOff], timeout: 0.5)
        XCTAssertEqual(fake.calls, ["onesignal", "directus", "onesignal", "directus"])
        XCTAssertEqual(fake.sentTagWrites.last, on("Songshan", above: 150).getTags())
        XCTAssertEqual(fake.mirrored?.alerts, StationAlerts(above: 150))
    }

    func testNewFavouriteCancelsAClearStillWaiting() throws {
        try storePending([126: ["Songshan"]])
        let fake = FakeServices(defaults: defaults)
        _ = run(fake)
        XCTAssertNil(FavouriteAlerts.pendingClears(defaults: defaults)[126])
    }

    // MARK: FOX-36 — the cap counts other stations (FOX-37 M3)

    func testCapCountsOtherStationsOnly() {
        // Its own "above" alert on and one other station: its "below" switch
        // adds no station, so it isn't locked.
        XCTAssertFalse(FavouriteAlerts.isAtCap(settings([on("Songshan"), on("Banqiao")]), excluding: "Songshan"))
        XCTAssertTrue(FavouriteAlerts.isAtCap(settings([on("Zhongshan"), on("Banqiao")]), excluding: "Songshan"))
        XCTAssertTrue(FavouriteAlerts.isAtCap(settings([on("Songshan"), on("Zhongshan"), on("Banqiao")]), excluding: "Songshan"))
        // Entries with both alerts off don't count.
        XCTAssertFalse(FavouriteAlerts.isAtCap(settings([on("Zhongshan", above: nil), on("Banqiao")]), excluding: "Songshan"))
        XCTAssertEqual(FavouriteAlerts.alertedStationCount(settings([on("Zhongshan", above: nil), on("Banqiao")])), 1)
    }

    // MARK: FOX-36 — leaving Favourites turns alerts off (FOX-37 M1, M4)

    private let removed = 9_001

    private func storePending(_ pending: [Int: [String]]) throws {
        let stored = Dictionary(uniqueKeysWithValues: pending.map { (String($0.key), $0.value) })
        defaults.set(try JSONEncoder().encode(stored), forKey: "favouriteAlertsPendingClears")
    }

    private func clear(_ fake: FakeServices, codes: [String]) -> Bool? {
        let done = expectation(description: "cleared")
        var cleared: Bool?
        FavouriteAlerts.clear(stationId: removed, tagCodes: codes, services: fake.services) {
            XCTAssertTrue(Thread.isMainThread)
            cleared = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        return cleared
    }

    func testStationScreenClearsEveryCandidateWhileAlertStateIsUnknown() {
        // The station record says where this app writes alerts, not where
        // an alert of unknown state is.
        XCTAssertEqual(DetailsViewModel.tagCodesToClear(alertsOn: nil, exactTagCode: "Songshan", candidates: ["126"]), ["126", "Songshan"])
        XCTAssertEqual(DetailsViewModel.tagCodesToClear(alertsOn: nil, exactTagCode: nil, candidates: ["Songshan", "126"]), ["126", "Songshan"])
        XCTAssertEqual(DetailsViewModel.tagCodesToClear(alertsOn: true, exactTagCode: "Songshan", candidates: ["Songshan", "126"]), ["Songshan"])
        XCTAssertEqual(DetailsViewModel.tagCodesToClear(alertsOn: false, exactTagCode: "Songshan", candidates: ["Songshan", "126"]), [])
    }

    func testFavouriteAfterTheStationRecordFailedSaysSoAndTryAgainStillEnables() {
        var deferred = DeferredAlertsEnable()
        // Opened offline: the latest request already failed, then the heart.
        XCTAssertEqual(deferred.favourited(isAwaitingStation: false), .tellNotChanged)
        XCTAssertTrue(deferred.isWaiting)
        // Try Again fails too: told once already.
        XCTAssertEqual(deferred.stationAnswered(hasStation: false, isLatest: true), .nothing)
        // Try Again loads the record: alerts go on.
        XCTAssertEqual(deferred.stationAnswered(hasStation: true, isLatest: true), .enable)
        XCTAssertFalse(deferred.isWaiting)
        XCTAssertEqual(deferred.stationAnswered(hasStation: true, isLatest: true), .nothing)
    }

    func testFavouriteWhileTheStationRecordIsOnTheWireWaitsForTheLatestAnswer() {
        var deferred = DeferredAlertsEnable()
        XCTAssertEqual(deferred.favourited(isAwaitingStation: true), .nothing)
        // A failure from an older pair while the latest is still on the wire.
        XCTAssertEqual(deferred.stationAnswered(hasStation: false, isLatest: false), .nothing)
        XCTAssertTrue(deferred.isWaiting)
        XCTAssertEqual(deferred.stationAnswered(hasStation: true, isLatest: true), .enable)

        // The latest failing does say so.
        var failed = DeferredAlertsEnable()
        _ = failed.favourited(isAwaitingStation: true)
        XCTAssertEqual(failed.stationAnswered(hasStation: false, isLatest: true), .tellNotChanged)
    }

    func testUnfavouriteStopsAWaitingEnable() {
        var deferred = DeferredAlertsEnable()
        _ = deferred.favourited(isAwaitingStation: true)
        deferred.cancel()
        XCTAssertEqual(deferred.stationAnswered(hasStation: true, isLatest: true), .nothing)
        var neverFavourited = DeferredAlertsEnable()
        XCTAssertEqual(neverFavourited.stationAnswered(hasStation: false, isLatest: true), .nothing)
    }

    func testTagCodesToClearWhenStateIsKnownOrNot() {
        let candidates = ["Songshan", "126"]
        XCTAssertEqual(FavouriteAlerts.tagCodesToClear(alertsOn: false, knownTagCode: "Songshan", candidates: candidates), [])
        XCTAssertEqual(FavouriteAlerts.tagCodesToClear(alertsOn: true, knownTagCode: "Songshan", candidates: candidates), ["Songshan"])
        XCTAssertEqual(FavouriteAlerts.tagCodesToClear(alertsOn: true, knownTagCode: nil, candidates: candidates), candidates)
        // No record and OneSignal not read: cleared anyway, under every prefix.
        XCTAssertEqual(FavouriteAlerts.tagCodesToClear(alertsOn: nil, knownTagCode: nil, candidates: candidates), candidates)
    }

    func testClearWritesOneSignalThenDirectusThenSaysOff() {
        let fake = FakeServices(defaults: defaults)
        let posted = expectation(forNotification: FavouriteAlerts.changed, object: nil) { [removed] notification in
            FavouriteAlerts.isOn(in: notification, stationId: removed) == false
        }

        XCTAssertEqual(clear(fake, codes: ["Songshan", "126", "Songshan"]), true)
        wait(for: [posted], timeout: 2)
        XCTAssertEqual(fake.calls, ["onesignal", "directus"])
        XCTAssertEqual(fake.sentTagWrites.count, 1)
        XCTAssertEqual(fake.sentTags, [
            "Songshan": "", "Songshan_pollution_therhold": "", "Songshan_cleanliness_therhold": "",
            "126": "", "126_pollution_therhold": "", "126_cleanliness_therhold": "",
        ])
        XCTAssertEqual(fake.mirrored?.stationId, removed)
        XCTAssertEqual(fake.mirrored?.alerts, .off)
        XCTAssertEqual(fake.mirroredSettled, true)
        XCTAssertTrue(FavouriteAlerts.pendingClears(defaults: defaults).isEmpty)
    }

    func testClearOneSignalFailureSkipsDirectusAndIsKeptForLater() {
        let fake = FakeServices(defaults: defaults)
        fake.send = .failure(.oneSignalError)
        let posted = expectation(forNotification: FavouriteAlerts.changed, object: nil) { [removed] notification in
            FavouriteAlerts.isOn(in: notification, stationId: removed) != nil
        }
        posted.isInverted = true

        XCTAssertEqual(clear(fake, codes: ["Songshan"]), false)
        wait(for: [posted], timeout: 0.3)
        XCTAssertEqual(fake.calls, ["onesignal"])
        XCTAssertNil(fake.mirrored)
        XCTAssertEqual(FavouriteAlerts.pendingClears(defaults: defaults), [removed: ["Songshan"]])
    }

    func testPendingClearsAreRetriedUnlessFavouritedAgain() throws {
        try storePending([removed: ["Songshan"], 126: ["126"]])
        let fake = FakeServices(defaults: defaults)
        let posted = expectation(forNotification: FavouriteAlerts.changed, object: nil) { [removed] notification in
            FavouriteAlerts.isOn(in: notification, stationId: removed) == false
        }

        FavouriteAlerts.retryPendingClears(isFavourite: { $0 == 126 }, services: fake.services)
        wait(for: [posted], timeout: 2)
        XCTAssertEqual(fake.calls, ["onesignal", "directus"])
        XCTAssertEqual(fake.sentTags?["Songshan_pollution_therhold"], "")
        XCTAssertNil(fake.sentTags?["126_pollution_therhold"])
        XCTAssertTrue(FavouriteAlerts.pendingClears(defaults: defaults).isEmpty)
    }

    // MARK: FOX-36 — Help's "cancel all" (FOX-37 M1)

    private func cancelAll(_ fake: FakeServices) -> Bool? {
        let done = expectation(description: "cancelled")
        var cancelled: Bool?
        FavouriteAlerts.cancelAll(services: fake.services) {
            XCTAssertTrue(Thread.isMainThread)
            cancelled = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        return cancelled
    }

    func testCancelAllWritesOneSignalThenDirectus() throws {
        try storePending([removed: ["Songshan"]])
        let fake = FakeServices(defaults: defaults)
        fake.read = .success(settings([on("Banqiao"), on("901", above: nil, below: 20)]))

        XCTAssertEqual(cancelAll(fake), true)
        XCTAssertEqual(fake.calls, ["read", "onesignal", "directus-cancel-all"])
        XCTAssertEqual(fake.sentTags?["Banqiao_pollution_therhold"], "")
        XCTAssertEqual(fake.sentTags?["901_cleanliness_therhold"], "")
        XCTAssertTrue(FavouriteAlerts.pendingClears(defaults: defaults).isEmpty)
    }

    func testCancelAllAlsoClearsWaitingClearsAndUnreadableTags() throws {
        try storePending([removed: ["Xindian"]])
        let fake = FakeServices(defaults: defaults)
        var read = settings([])
        read.unreadableStationTagCodes = ["Banqiao"]
        fake.read = .success(read)

        XCTAssertEqual(cancelAll(fake), true)
        XCTAssertEqual(fake.calls, ["read", "onesignal", "directus-cancel-all"])
        XCTAssertEqual(fake.sentTags?["Xindian_pollution_therhold"], "")
        XCTAssertEqual(fake.sentTags?["Banqiao_pollution_therhold"], "")
        XCTAssertTrue(FavouriteAlerts.pendingClears(defaults: defaults).isEmpty)
    }

    func testCancelAllRefusedKeepsWaitingClears() throws {
        try storePending([removed: ["Xindian"]])
        let fake = FakeServices(defaults: defaults)
        fake.send = .failure(.oneSignalError)
        XCTAssertEqual(cancelAll(fake), false)
        XCTAssertEqual(FavouriteAlerts.pendingClears(defaults: defaults), [removed: ["Xindian"]])
    }

    func testCancelAllWithNothingOnStillClearsTheDirectusCopy() {
        let fake = FakeServices(defaults: defaults)
        XCTAssertEqual(cancelAll(fake), true)
        XCTAssertEqual(fake.calls, ["read", "directus-cancel-all"])
    }

    func testCancelAllLeavesDirectusWhenOneSignalCantBeRead() {
        let fake = FakeServices(defaults: defaults)
        fake.read = .failure(.oneSignalError)
        XCTAssertEqual(cancelAll(fake), false)
        XCTAssertEqual(fake.calls, ["read"])
    }

    func testCancelAllLeavesDirectusWhenOneSignalRefusesTheWrite() {
        let fake = FakeServices(defaults: defaults)
        fake.read = .success(settings([on("Banqiao")]))
        fake.send = .failure(.oneSignalError)
        XCTAssertEqual(cancelAll(fake), false)
        XCTAssertEqual(fake.calls, ["read", "onesignal"])
    }

    // MARK: FOX-36 — the station screen's switches (FOX-37 M1)

    private func write(_ fake: FakeServices, isCurrent: Bool = true) -> Bool? {
        let done = expectation(description: "written")
        var taken: Bool?
        FavouriteAlerts.write(on("Songshan", above: 150), stationId: 126, siteId: "012", isCurrent: { isCurrent }, services: fake.services) {
            XCTAssertTrue(Thread.isMainThread)
            taken = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        return taken
    }

    func testSwitchWriteCopiesToDirectusOnlyAfterOneSignal() {
        let fake = FakeServices(defaults: defaults)
        XCTAssertEqual(write(fake), true)
        XCTAssertEqual(fake.calls, ["onesignal", "directus"])
        XCTAssertEqual(fake.sentTags, on("Songshan", above: 150).getTags())
        XCTAssertEqual(fake.mirrored?.alerts, StationAlerts(above: 150))
        XCTAssertEqual(fake.mirrored?.siteId, "012")
        // A slider sends a value per step: the copy waits for it to settle.
        XCTAssertEqual(fake.mirroredSettled, false)
    }

    func testSwitchWriteOneSignalFailureSkipsDirectus() {
        let fake = FakeServices(defaults: defaults)
        fake.send = .failure(.oneSignalError)
        XCTAssertEqual(write(fake), false)
        XCTAssertEqual(fake.calls, ["onesignal"])
        XCTAssertNil(fake.mirrored)
    }

    func testSwitchWriteOvertakenByALaterChangeLeavesTheCopyToIt() {
        let fake = FakeServices(defaults: defaults)
        XCTAssertEqual(write(fake, isCurrent: false), true)
        XCTAssertEqual(fake.calls, ["onesignal"])
    }
}
