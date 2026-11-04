//
//  WidgetRelevanceTests.swift
//  TWAQITests
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest

@testable import Taiwan_Air

/// FOX-75: the widget's relevance score and the watch Smart Stack's windows.
final class WidgetRelevanceTests: XCTestCase {
    private static let taipei = TimeZone(identifier: "Asia/Taipei")!

    /// 2026-11-04 10:20 in Taiwan.
    private let now = WidgetRelevanceTests.taipeiDate(2026, 11, 4, 10, 20)

    // MARK: - Helpers

    private static func taipeiDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = taipei
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// `publish_time` as the API sends it: Taiwan local time, no zone.
    private static func publishTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = taipei
        return formatter.string(from: date)
    }

    /// A reading published `minutesAgo` before `now` (10:00 by default).
    private func reading(
        stationId: Int = 1, aqi: Double, pm25: Double = 10, publishTime: String? = nil, minutesAgo: Double = 20
    ) -> WatchReading {
        let json: [String: Any] = [
            "stationId": stationId, "code": "S\(stationId)", "name": "Station", "nameLocal": "測站",
            "aqi": aqi, "pm25": pm25, "pm10": 20, "o3": 30, "co": 0.3, "so2": 1, "no2": 10,
            "windDirection": 0, "windSpeed": 1,
            "publishTime": publishTime ?? Self.publishTime(now.addingTimeInterval(-minutesAgo * 60)),
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(WatchReading.self, from: data)
    }

    private func score(
        _ reading: WatchReading?, _ type: AirIndexTypes = .aqi,
        previous: WatchReading? = nil, threshold: Int? = nil, isLocked: Bool = false
    ) -> Float {
        WidgetRelevance.score(
            for: reading, airIndexType: type, previous: previous,
            alertThreshold: threshold, isLocked: isLocked, now: now
        )
    }

    // MARK: - Levels

    func testEachLevelScoresHigherThanTheOneBelow() {
        let aqis: [(Double, Float)] = [(30, 10), (80, 25), (120, 50), (170, 70), (250, 85), (350, 90)]
        for (aqi, expected) in aqis {
            XCTAssertEqual(score(reading(aqi: aqi)), expected, "AQI \(aqi)")
        }
        let levels = AirStatuses.getShowAllCases().map(WidgetRelevance.levelScore)
        XCTAssertEqual(levels, levels.sorted())
        XCTAssertEqual(Set(levels).count, levels.count)
    }

    func testGoodStaysLowAndSensitiveGroupsAndAboveScoreHigh() {
        XCTAssertLessThanOrEqual(score(reading(aqi: 30)), 10)
        XCTAssertGreaterThanOrEqual(score(reading(aqi: 101)), 50)
    }

    func testNoReadingOrNoLevelScoresZero() {
        XCTAssertEqual(score(nil), 0)
        XCTAssertEqual(score(reading(aqi: 0)), 0)
    }

    func testUsesTheLevelOfTheIndexShown() {
        // Good AQI, but PM2.5 unhealthy.
        let mixed = reading(aqi: 40, pm25: 60)
        XCTAssertEqual(score(mixed, .aqi), 10)
        XCTAssertEqual(score(mixed, .pm25), 70)
    }

    /// One scale for every index, and so for the iPhone and the watch, which
    /// call the same function: a level scores the same whichever index got it.
    func testSameLevelScoresTheSameOnEveryIndex() {
        let aqiUnhealthy = score(reading(aqi: 170, pm25: 5), .aqi)
        let pm25Unhealthy = score(reading(aqi: 30, pm25: 60), .pm25)
        XCTAssertEqual(aqiUnhealthy, pm25Unhealthy)

        for status in AirStatuses.getShowAllCases() {
            XCTAssertLessThanOrEqual(WidgetRelevance.levelScore(status), WidgetRelevance.maxScore)
        }
    }

    // MARK: - Worsening

    func testWorseningAddsToTheScore() {
        let previous = reading(aqi: 110, minutesAgo: 80)
        XCTAssertEqual(score(reading(aqi: 130), previous: previous), 55)
    }

    func testImprovingOrSteadyAddsNothing() {
        XCTAssertEqual(score(reading(aqi: 110), previous: reading(aqi: 130, minutesAgo: 80)), 50)
        XCTAssertEqual(score(reading(aqi: 110), previous: reading(aqi: 110, minutesAgo: 80)), 50)
    }

    func testWorseningNeverOutranksTheNextLevel() {
        let worseGood = score(reading(aqi: 50), previous: reading(aqi: 20, minutesAgo: 80))
        XCTAssertLessThan(worseGood, score(reading(aqi: 51)))
        let worseHazardous = score(reading(aqi: 400), previous: reading(aqi: 350, minutesAgo: 80))
        XCTAssertLessThanOrEqual(worseHazardous, WidgetRelevance.maxScore)
    }

    func testAnotherStationsReadingIsNotAPreviousOne() {
        let other = reading(stationId: 2, aqi: 20, minutesAgo: 80)
        XCTAssertEqual(score(reading(aqi: 130), previous: other), 50)
    }

    // MARK: - Stale data

    func testStaleDataScoresZero() {
        let old = reading(aqi: 250, minutesAgo: 3 * 60 + 1)
        XCTAssertEqual(score(old), 0)
        XCTAssertEqual(score(old, threshold: 100), 0)
    }

    func testDataJustInsideTheLimitStillScores() {
        XCTAssertEqual(score(reading(aqi: 250, minutesAgo: 3 * 60)), 85)
    }

    func testUnreadablePublishTimeScoresZero() {
        XCTAssertEqual(score(reading(aqi: 250, publishTime: "")), 0)
        XCTAssertEqual(score(WatchReading.placeholder), 0)
    }

    // MARK: - Alert threshold

    func testAtOrOverTheAlertThresholdScoresTheMaximum() {
        XCTAssertEqual(score(reading(aqi: 120), threshold: 120), WidgetRelevance.maxScore)
        XCTAssertEqual(score(reading(aqi: 160), threshold: 120), WidgetRelevance.maxScore)
    }

    func testUnderTheAlertThresholdScoresByLevel() {
        XCTAssertEqual(score(reading(aqi: 119), threshold: 120), 50)
    }

    func testThresholdIsOnTheAqiWhateverIndexIsShown() {
        XCTAssertEqual(score(reading(aqi: 130, pm25: 10), .pm25, threshold: 120), WidgetRelevance.maxScore)
        XCTAssertEqual(score(reading(aqi: 60, pm25: 60), .pm25, threshold: 120), 70)
    }

    func testThresholdOutranksEveryLevel() {
        let hazardousWorsening = score(reading(aqi: 400), previous: reading(aqi: 350, minutesAgo: 80))
        XCTAssertLessThan(hazardousWorsening, score(reading(aqi: 60), threshold: 50))
    }

    func testLockedScoresZero() {
        XCTAssertEqual(score(reading(aqi: 250), threshold: 100, isLocked: true), 0)
    }

    // MARK: - Previous publish

    func testHistoryKeepsTheLatestTwoPublishesOfAStation() {
        let nine = reading(aqi: 50, minutesAgo: 80)
        let ten = reading(aqi: 70, minutesAgo: 20)
        var history = WidgetRelevance.recording(nine, in: [])
        history = WidgetRelevance.recording(ten, in: history)
        XCTAssertEqual(WidgetRelevance.previous(of: ten, in: history), nine)

        let eleven = reading(aqi: 90, publishTime: Self.publishTime(now.addingTimeInterval(40 * 60)))
        history = WidgetRelevance.recording(eleven, in: history)
        XCTAssertEqual(history.filter { $0.stationId == 1 }, [ten, eleven])
        XCTAssertEqual(WidgetRelevance.previous(of: eleven, in: history), ten)
    }

    /// Two refreshes inside one hour see the same publish: the one before it
    /// stays the previous one, so worsening isn't lost on the second refresh.
    func testRecordingTheSamePublishAgainKeepsThePreviousOne() {
        let nine = reading(aqi: 50, minutesAgo: 80)
        let ten = reading(aqi: 70, minutesAgo: 20)
        var history = WidgetRelevance.recording(ten, in: WidgetRelevance.recording(nine, in: []))
        history = WidgetRelevance.recording(ten, in: history)
        XCTAssertEqual(history, [nine, ten])
        XCTAssertEqual(WidgetRelevance.previous(of: ten, in: history), nine)
    }

    func testAnOlderReadingDoesNotReplaceANewerOne() {
        let nine = reading(aqi: 50, minutesAgo: 80)
        let ten = reading(aqi: 70, minutesAgo: 20)
        let history = WidgetRelevance.recording(ten, in: [])
        XCTAssertEqual(WidgetRelevance.recording(nine, in: history), history)
    }

    func testStationsAreKeptApartAndTheHistoryIsBounded() {
        let one = reading(stationId: 1, aqi: 50)
        let two = reading(stationId: 2, aqi: 60)
        let history = WidgetRelevance.recording(two, in: WidgetRelevance.recording(one, in: []))
        XCTAssertNil(WidgetRelevance.previous(of: two, in: history))

        var many: [WatchReading] = []
        for id in 1...(WidgetRelevance.historyLimit + 5) {
            many = WidgetRelevance.recording(reading(stationId: id, aqi: 50), in: many)
        }
        XCTAssertEqual(many.count, WidgetRelevance.historyLimit)
        XCTAssertEqual(many.last?.stationId, WidgetRelevance.historyLimit + 5)
    }

    // MARK: - Stored in the app group

    func testAlertThresholdsRoundTripThroughTheAppGroup() {
        let saved = WatchStore.alertThresholds
        defer { WatchStore.alertThresholds = saved }

        WatchStore.alertThresholds = [12: 120, 345: 80]
        XCTAssertEqual(WatchStore.alertThresholds, [12: 120, 345: 80])
        WatchStore.alertThresholds = [:]
        XCTAssertEqual(WatchStore.alertThresholds, [:])
    }

    /// Against the real clock: the store leaves out readings a week old.
    func testRecordForRelevanceReturnsTheEarlierPublish() {
        let saved = WatchStore.relevanceHistory
        defer { WatchStore.relevanceHistory = saved }
        WatchStore.relevanceHistory = []

        let earlier = reading(aqi: 50, publishTime: Self.publishTime(Date().addingTimeInterval(-80 * 60)))
        let later = reading(aqi: 70, publishTime: Self.publishTime(Date().addingTimeInterval(-20 * 60)))
        XCTAssertNil(WatchStore.recordForRelevance(earlier))
        XCTAssertEqual(WatchStore.recordForRelevance(later), earlier)
        // The next refresh in the same hour still sees the earlier publish.
        XCTAssertEqual(WatchStore.recordForRelevance(later), earlier)
        XCTAssertEqual(WatchStore.relevanceHistory, [earlier, later])
    }

    // MARK: - Smart Stack windows

    /// The windows are Taiwan clock times even when the device is set to
    /// another zone.
    func testCommuteWindowsAreInTaipeiNotTheDeviceZone() {
        let saved = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        defer { NSTimeZone.default = saved }

        // 05:00 in Taiwan: both of today's windows are ahead.
        let early = Self.taipeiDate(2026, 11, 4, 5, 0)
        let windows = SmartStackWindows.commuteIntervals(from: early, days: 1)
        XCTAssertEqual(windows, [
            DateInterval(start: Self.taipeiDate(2026, 11, 4, 6, 30), end: Self.taipeiDate(2026, 11, 4, 9, 0)),
            DateInterval(start: Self.taipeiDate(2026, 11, 4, 17, 0), end: Self.taipeiDate(2026, 11, 4, 19, 30)),
        ])
        // 06:30 Taipei is 22:30 UTC the day before.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.dateComponents([.day, .hour, .minute], from: windows[0].start)
        XCTAssertEqual(start, DateComponents(day: 3, hour: 22, minute: 30))
    }

    func testWindowsAlreadyOverAreLeftOutAndARunningOneKept() {
        // 08:00: the morning commute is running, the evening one ahead.
        let morning = Self.taipeiDate(2026, 11, 4, 8, 0)
        let today = SmartStackWindows.commuteIntervals(from: morning, days: 1)
        XCTAssertEqual(today.first?.start, Self.taipeiDate(2026, 11, 4, 6, 30))
        XCTAssertEqual(today.count, 2)

        // 20:00: today is done; tomorrow's two remain.
        let evening = Self.taipeiDate(2026, 11, 4, 20, 0)
        let ahead = SmartStackWindows.commuteIntervals(from: evening, days: 2)
        XCTAssertEqual(ahead.map(\.start), [
            Self.taipeiDate(2026, 11, 5, 6, 30),
            Self.taipeiDate(2026, 11, 5, 17, 0),
        ])
    }

    func testCommuteWindowsCoverTheDaysAhead() {
        let windows = SmartStackWindows.commuteIntervals(from: Self.taipeiDate(2026, 11, 4, 5, 0))
        XCTAssertEqual(windows.count, SmartStackWindows.daysAhead * SmartStackWindows.commutes.count)
    }

    func testAlertWindowRunsTwoHoursFromThePublish() {
        let over = reading(aqi: 130, minutesAgo: 20)
        let window = SmartStackWindows.alertInterval(for: over, threshold: 120, now: now)
        XCTAssertEqual(window?.start, Self.taipeiDate(2026, 11, 4, 10, 0))
        XCTAssertEqual(window?.duration, 2 * 60 * 60)
    }

    func testNoAlertWindowUnderTheThresholdOrOnceOver() {
        XCTAssertNil(SmartStackWindows.alertInterval(for: reading(aqi: 119), threshold: 120, now: now))
        XCTAssertNil(SmartStackWindows.alertInterval(for: reading(aqi: 200, minutesAgo: 121), threshold: 120, now: now))
        XCTAssertNil(SmartStackWindows.alertInterval(for: reading(aqi: 200, publishTime: ""), threshold: 120, now: now))
    }
}
