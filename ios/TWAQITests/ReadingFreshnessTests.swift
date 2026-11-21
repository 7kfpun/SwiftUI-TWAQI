//
//  ReadingFreshnessTests.swift
//  TWAQITests
//
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest

@testable import Taiwan_Air

/// The stale/fresh decision (TWAQ-19). `publish_time` is Taiwan local time.
final class ReadingFreshnessTests: XCTestCase {
    private let publish = "2026-08-07T22:00:00"

    /// 22:00 in Taipei is 14:00 UTC.
    private var publishDate: Date { Date.fromApi(publish)! }

    private func decide(minutesLater: Double, cache: Bool = false) -> ReadingFreshness {
        ReadingFreshness.decide(
            publishTime: publish,
            isFromCache: cache,
            now: publishDate.addingTimeInterval(minutesLater * 60)
        )
    }

    // MARK: Boundaries

    func testJustPublishedIsFresh() {
        XCTAssertEqual(decide(minutesLater: 0), .fresh)
    }

    func testAnHourOldIsStillFresh() {
        XCTAssertEqual(decide(minutesLater: 60), .fresh)
    }

    func testExactlyNinetyMinutesIsStillFresh() {
        XCTAssertEqual(decide(minutesLater: 90), .fresh)
    }

    func testJustPastNinetyMinutesIsStale() {
        XCTAssertEqual(ReadingFreshness.decide(
            publishTime: publish,
            isFromCache: false,
            now: publishDate.addingTimeInterval(ReadingFreshness.staleAfter + 1)
        ), .stale)
    }

    func testADayOldIsStale() {
        XCTAssertEqual(decide(minutesLater: 24 * 60), .stale)
    }

    func testPublishTimeAheadOfTheClockIsFresh() {
        XCTAssertEqual(decide(minutesLater: -5), .fresh)
    }

    // MARK: Missing or unreadable

    func testMissingPublishTimeIsStale() {
        XCTAssertEqual(ReadingFreshness.decide(publishTime: nil, isFromCache: false), .stale)
    }

    func testUnreadablePublishTimeIsStale() {
        XCTAssertEqual(ReadingFreshness.decide(publishTime: "garbage", isFromCache: false), .stale)
        XCTAssertEqual(ReadingFreshness.decide(publishTime: "2026-08-07T22:00:00Z", isFromCache: false), .stale)
    }

    // MARK: Offline

    func testSavedCopyIsOfflineEvenWhenRecent() {
        XCTAssertEqual(decide(minutesLater: 5, cache: true), .offline)
    }

    func testSavedCopyIsOfflineWhenOld() {
        XCTAssertEqual(decide(minutesLater: 3 * 24 * 60, cache: true), .offline)
    }

    func testSavedCopyWithoutPublishTimeIsOffline() {
        XCTAssertEqual(ReadingFreshness.decide(publishTime: nil, isFromCache: true), .offline)
    }

    // MARK: Asia/Taipei

    /// Read as the device zone, 22:00 would be 8 hours off for anyone outside
    /// Taiwan and flip fresh to stale. The age must not depend on it.
    func testAgeIsTaipeiTimeWhateverTheDeviceZone() {
        // 22:30 Taipei is 14:30 UTC: 30 minutes after the publish time.
        let utc = ISO8601DateFormatter().date(from: "2026-08-07T14:30:00Z")!
        XCTAssertEqual(ReadingFreshness.age(of: publish, now: utc), 30 * 60)
        XCTAssertEqual(ReadingFreshness.decide(publishTime: publish, isFromCache: false, now: utc), .fresh)
    }

    func testTaipeiMidnightRolloverIsNotADayOld() {
        // Published 23:30 on the 7th, now 00:15 on the 8th, Taipei time.
        let now = Date.fromApi("2026-08-08T00:15:00")!
        XCTAssertEqual(ReadingFreshness.age(of: "2026-08-07T23:30:00", now: now), 45 * 60)
        XCTAssertEqual(ReadingFreshness.decide(publishTime: "2026-08-07T23:30:00", isFromCache: false, now: now), .fresh)
    }

    // MARK: Age text

    func testAgeTextForUnreadableTimeIsEmpty() {
        XCTAssertEqual(ReadingFreshness.ageText(of: nil), "")
        XCTAssertEqual(ReadingFreshness.ageText(of: "garbage"), "")
    }

    func testAgeTextIsNotEmptyForAReadableTime() {
        let text = ReadingFreshness.ageText(of: publish, now: publishDate.addingTimeInterval(12 * 60))
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("12"), text)
    }

    // MARK: Refresh gate

    func testRefreshGateResumesWaitersWhenTheRequestAnswers() async {
        let gate = RefreshGate()
        let waiting = Task { await gate.wait(); return true }
        // Give the task time to start waiting; finish() before wait() is not
        // a state the screens reach (answers arrive on the main queue later).
        try? await Task.sleep(nanoseconds: 100_000_000)
        await MainActor.run { gate.finish() }
        let done = await waiting.value
        XCTAssertTrue(done)
    }
}
