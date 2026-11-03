//
//  LockedComplicationLogTests.swift
//  TWAQITests
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

/// A free reader's locked watch complication reaches Firebase once per setup,
/// by way of the phone (FOX-63, FOX-44).
final class LockedComplicationLogTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let circular = LockedComplicationHit(style: "labelled", family: "accessoryCircular", index: "aqi")

    override func setUp() {
        super.setUp()
        suiteName = "LockedComplicationLogTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// Timelines rebuild every 30 minutes; only the first one counts.
    func testASetupCountsOnceAcrossTimelineRebuilds() {
        XCTAssertTrue(LockedComplicationLog.record(circular, in: defaults))
        XCTAssertFalse(LockedComplicationLog.record(circular, in: defaults))
        XCTAssertEqual(LockedComplicationLog.pending(in: defaults), [circular])
    }

    /// Still once after the queue was sent: sending isn't a new encounter.
    func testASentSetupIsNotCountedAgain() {
        LockedComplicationLog.record(circular, in: defaults)
        XCTAssertEqual(LockedComplicationLog.drain(from: defaults), [circular])
        XCTAssertFalse(LockedComplicationLog.record(circular, in: defaults))
        XCTAssertEqual(LockedComplicationLog.drain(from: defaults), [])
    }

    func testEachStyleFamilyAndIndexCountsSeparately() {
        let hits = [
            circular,
            LockedComplicationHit(style: "status", family: "accessoryCircular", index: "aqi"),
            LockedComplicationHit(style: "labelled", family: "accessoryCorner", index: "aqi"),
            LockedComplicationHit(style: "labelled", family: "accessoryCircular", index: "pm25"),
        ]
        for hit in hits {
            XCTAssertTrue(LockedComplicationLog.record(hit, in: defaults))
        }
        XCTAssertEqual(LockedComplicationLog.drain(from: defaults), hits)
        XCTAssertEqual(LockedComplicationLog.pending(in: defaults), [])
    }

    func testTheQueueIsBounded() {
        for number in 0..<(LockedComplicationLog.maxPending + 5) {
            LockedComplicationLog.record(
                LockedComplicationHit(style: "labelled", family: "accessoryCircular", index: "\(number)"),
                in: defaults
            )
        }
        XCTAssertEqual(LockedComplicationLog.pending(in: defaults).count, LockedComplicationLog.maxPending)
    }

    /// What the watch sends is what the phone reads back, as property-list
    /// types WatchConnectivity accepts.
    func testThePayloadSurvivesTheTrip() throws {
        let hits = [circular, LockedComplicationHit(style: "numberOnly", family: "accessoryInline", index: "o3")]
        let userInfo = LockedComplicationLog.userInfo(for: hits)
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: userInfo, format: .binary, options: 0))
        XCTAssertEqual(LockedComplicationLog.hits(fromUserInfo: userInfo), hits)
    }

    func testOtherPayloadsAreIgnored() {
        XCTAssertEqual(LockedComplicationLog.hits(fromUserInfo: [:]), [])
        XCTAssertEqual(LockedComplicationLog.hits(fromUserInfo: ["other": 1]), [])
        XCTAssertEqual(LockedComplicationLog.hits(fromUserInfo: [LockedComplicationLog.userInfoKey: [["style": "face"]]]), [])
    }

    /// The phone logs one `watch_complication_locked` per hit, with only the
    /// style, family and index.
    func testThePhoneLogsEachHitAsTheFirebaseEvent() {
        var logged: [(AnalyticsEvent, [String: String])] = []
        WatchEventRelay.logEvents(fromUserInfo: LockedComplicationLog.userInfo(for: [circular])) { event, parameters in
            logged.append((event, parameters as? [String: String] ?? [:]))
        }
        XCTAssertEqual(logged.count, 1)
        XCTAssertEqual(logged.first?.0, .watchComplicationLocked)
        XCTAssertEqual(logged.first?.1, ["style": "labelled", "family": "accessoryCircular", "index": "aqi"])
        XCTAssertEqual(AnalyticsEvent.watchComplicationLocked.rawValue, "watch_complication_locked")
    }
}
