//
//  PollutantHistoryTests.swift
//  TWAQITests
//
//  Created by kf on 21/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class PollutantHistoryTests: XCTestCase {
    /// `hoursAgo` counts back from 2026-11-21 12:00, Taiwan time.
    private func reading(hoursAgo: Int, pm25: Double = 10, aqi: Double = 40) -> HistoricalPollutant {
        let newest = Date.fromApi("2026-11-21T12:00:00")!
        let date = newest.addingTimeInterval(-Double(hoursAgo) * 3600)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .taipei
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return HistoricalPollutant(
            aqi: aqi, pm25: pm25, pm10: 20, no2: 1, so2: 1, co: 0.1, o3: 30,
            windDirection: 90, windSpeed: 2, publishTime: formatter.string(from: date)
        )
    }

    private func hourly(_ count: Int, pm25: (Int) -> Double = { Double($0) + 1 }) -> [HistoricalPollutant] {
        // Oldest first, like the API.
        (0..<count).reversed().map { reading(hoursAgo: $0, pm25: pm25($0)) }
    }

    // MARK: Range slicing

    func testDayKeepsTheNewest24Hours() {
        let series = PollutantHistorySeries.make(readings: hourly(100), airIndexType: .pm25, range: .day)

        XCTAssertEqual(series.samples.count, 24)
        XCTAssertEqual(series.samples.last?.value, 1)   // hoursAgo 0
        XCTAssertEqual(series.samples.first?.value, 24) // hoursAgo 23
        XCTAssertFalse(series.isShorterThanRange)
    }

    func testWeekKeepsEverythingUpToSevenDays() {
        let series = PollutantHistorySeries.make(readings: hourly(200), airIndexType: .pm25, range: .week)

        XCTAssertEqual(series.samples.count, 168)
        XCTAssertEqual(series.samples.first?.value, 168)
    }

    func testWeekIsShorterWhenTheHistoryIs() {
        let series = PollutantHistorySeries.make(readings: hourly(100), airIndexType: .pm25, range: .week)

        XCTAssertEqual(series.coveredHours, 100)
        XCTAssertTrue(series.isShorterThanRange)
    }

    func testWindowEndsOnTheNewestReadingNotNow() {
        // Readings are from 2026, long before "now" in any test run.
        let series = PollutantHistorySeries.make(readings: hourly(5), airIndexType: .pm25, range: .day)

        XCTAssertEqual(series.samples.count, 5)
        XCTAssertEqual(series.samples.last?.time, Date.fromApi("2026-11-21T12:00:00"))
    }

    func testReadingsInAnyOrderGiveTheSameSeries() {
        let ordered = PollutantHistorySeries.make(readings: hourly(30), airIndexType: .pm25, range: .day)
        let shuffled = PollutantHistorySeries.make(readings: hourly(30).reversed(), airIndexType: .pm25, range: .day)

        XCTAssertEqual(ordered, shuffled)
    }

    func testEmptyHistoryIsEmptyAndNotChartable() {
        let series = PollutantHistorySeries.make(readings: [], airIndexType: .pm25, range: .week)

        XCTAssertTrue(series.samples.isEmpty)
        XCTAssertFalse(series.isChartable)
        XCTAssertNil(series.latest)
        XCTAssertNil(series.index(atFraction: 0.5))
    }

    func testTimesAreReadAsTaiwanTime() {
        let series = PollutantHistorySeries.make(readings: [reading(hoursAgo: 0)], airIndexType: .pm25, range: .day)

        // 12:00 in Taipei is 04:00 UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.hour], from: series.samples.last!.time)
        XCTAssertEqual(parts.hour, 4)
    }

    // MARK: Gaps

    func testMissingHoursAreGapsNotZeros() {
        // Hours 0, 1, 4, 5 exist; 2 and 3 never arrived.
        let readings = [5, 4, 1, 0].map { reading(hoursAgo: $0, pm25: 10) }
        let series = PollutantHistorySeries.make(readings: readings, airIndexType: .pm25, range: .day)

        XCTAssertEqual(series.samples.count, 6)
        XCTAssertEqual(series.samples.map(\.value), [10, 10, nil, nil, 10, 10])
        XCTAssertEqual(series.runs, [[0, 1], [4, 5]])
    }

    func testZeroReadingIsAGap() {
        // Stations report 0.0 for what they don't measure.
        let readings = [reading(hoursAgo: 2), reading(hoursAgo: 1, pm25: 0), reading(hoursAgo: 0)]
        let series = PollutantHistorySeries.make(readings: readings, airIndexType: .pm25, range: .day)

        XCTAssertEqual(series.samples.map(\.value), [10, nil, 10])
        XCTAssertEqual(series.runs, [[0], [2]])
        XCTAssertEqual(series.values.count, 2)
    }

    func testGapAtTheNewestHourStaysInTheSeries() {
        let readings = [reading(hoursAgo: 2), reading(hoursAgo: 1), reading(hoursAgo: 0, pm25: 0)]
        let series = PollutantHistorySeries.make(readings: readings, airIndexType: .pm25, range: .day)

        // The window still ends on the newest reading's hour; latest skips the gap.
        XCTAssertEqual(series.samples.count, 3)
        XCTAssertNil(series.samples.last?.value)
        XCTAssertEqual(series.latest?.time, Date.fromApi("2026-11-21T11:00:00"))
    }

    func testUnparseableTimesAreDropped() {
        let bad = HistoricalPollutant(
            aqi: 1, pm25: 99, pm10: 1, no2: 1, so2: 1, co: 1, o3: 1, windDirection: 0, windSpeed: 0, publishTime: "soon"
        )
        let series = PollutantHistorySeries.make(readings: [reading(hoursAgo: 1), bad], airIndexType: .pm25, range: .day)

        XCTAssertEqual(series.samples.count, 1)
        XCTAssertEqual(series.values, [10])
    }

    func testDuplicateHourKeepsTheLaterReading() {
        let series = PollutantHistorySeries.make(
            readings: [reading(hoursAgo: 0, pm25: 10), reading(hoursAgo: 0, pm25: 25)],
            airIndexType: .pm25,
            range: .day
        )

        XCTAssertEqual(series.values, [25])
    }

    // MARK: Summary and scrubbing

    func testLowestHighestAndLatest() {
        let readings = [reading(hoursAgo: 3, pm25: 20), reading(hoursAgo: 2, pm25: 5),
                        reading(hoursAgo: 1, pm25: 40), reading(hoursAgo: 0, pm25: 12)]
        let series = PollutantHistorySeries.make(readings: readings, airIndexType: .pm25, range: .day)

        XCTAssertEqual(series.lowest?.value, 5)
        XCTAssertEqual(series.highest?.value, 40)
        XCTAssertEqual(series.latest?.value, 12)
    }

    func testEachPollutantReadsItsOwnField() {
        let readings = [reading(hoursAgo: 1, pm25: 10, aqi: 55), reading(hoursAgo: 0, pm25: 12, aqi: 60)]

        XCTAssertEqual(PollutantHistorySeries.make(readings: readings, airIndexType: .aqi, range: .day).values, [55, 60])
        XCTAssertEqual(PollutantHistorySeries.make(readings: readings, airIndexType: .pm25, range: .day).values, [10, 12])
    }

    func testScrubPositionMapsToAnHourAndClamps() {
        let series = PollutantHistorySeries.make(readings: hourly(11), airIndexType: .pm25, range: .day)

        XCTAssertEqual(series.index(atFraction: 0), 0)
        XCTAssertEqual(series.index(atFraction: 0.5), 5)
        XCTAssertEqual(series.index(atFraction: 1), 10)
        XCTAssertEqual(series.index(atFraction: -3), 0)
        XCTAssertEqual(series.index(atFraction: 9), 10)
    }

    // MARK: Cache

    func testCacheReadsBackAndIgnoresEmptyAndOld() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PollutantHistoryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date()
        let cache = PollutantHistoryCache(directory: directory, now: { now })

        XCTAssertNil(cache.readings(stationId: 91))

        cache.save(hourly(30), stationId: 91)
        XCTAssertEqual(cache.readings(stationId: 91), hourly(30))
        XCTAssertNil(cache.readings(stationId: 12))

        // An empty answer doesn't wipe the last good copy.
        cache.save([], stationId: 91)
        XCTAssertEqual(cache.readings(stationId: 91)?.count, 30)

        // Past a week it is not shown.
        now = now.addingTimeInterval(OfflineCacheRetention.maxAge + 60)
        XCTAssertNil(cache.readings(stationId: 91))
    }

    func testCacheFileIsOneThePurgeScans() {
        XCTAssertTrue(OfflineCacheRetention.isCacheFile(named: PollutantHistoryCache.fileName(stationId: 91)))
        XCTAssertEqual(
            PollutantCache.defaultDirectory,
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        )
    }
}
