//
//  ForecastStripTests.swift
//  TWAQITests
//
//  Created by kf on 22/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class ForecastStripTests: XCTestCase {

    private func period(_ start: String, _ end: String, wx: Int? = 4, pop: Double? = 10, minT: Double? = 20, maxT: Double? = 26) -> WeatherPeriod {
        WeatherPeriod(start: start, end: end, wx: wx, text: nil, pop: pop, minT: minT, maxT: maxT)
    }

    /// 2026-11-22 10:30 Taiwan time.
    private var now: Date { WeatherDates.parse("2026-11-22T10:30:00+08:00")! }

    private let periods = [
        "2026-11-22T06:00:00+08:00|2026-11-22T18:00:00+08:00",
        "2026-11-22T18:00:00+08:00|2026-11-23T06:00:00+08:00",
        "2026-11-23T06:00:00+08:00|2026-11-23T18:00:00+08:00",
    ]

    private func weatherPeriods() -> [WeatherPeriod] {
        periods.enumerated().map { index, pair in
            let parts = pair.split(separator: "|").map(String.init)
            return period(parts[0], parts[1], wx: index + 1, pop: Double(index * 10))
        }
    }

    // MARK: Day parts

    func testDayPartByTaiwanHour() {
        XCTAssertEqual(DayPart.of(hour: 0), .night)
        XCTAssertEqual(DayPart.of(hour: 5), .night)
        XCTAssertEqual(DayPart.of(hour: 6), .morning)
        XCTAssertEqual(DayPart.of(hour: 11), .morning)
        XCTAssertEqual(DayPart.of(hour: 12), .afternoon)
        XCTAssertEqual(DayPart.of(hour: 17), .afternoon)
        XCTAssertEqual(DayPart.of(hour: 18), .evening)
        XCTAssertEqual(DayPart.of(hour: 23), .evening)
    }

    // MARK: Weather cells

    func testTwelveHourPeriodsSplitIntoSixHourParts() {
        let cells = ForecastStrip.weatherCells(weatherPeriods(), now: now)
        // Now is 10:30: the morning part (06–12) is still running, then
        // afternoon, evening and night; the window ends at 10:30 tomorrow.
        XCTAssertEqual(cells.map(\.part), [.morning, .afternoon, .evening, .night, .morning])
        XCTAssertEqual(cells.map(\.wx), [1, 1, 2, 2, 3])
    }

    func testCellKeepsRealStartOfRunningPartAndPeriodValues() throws {
        let cells = ForecastStrip.weatherCells(weatherPeriods(), now: now)
        let first = try XCTUnwrap(cells.first)
        XCTAssertEqual(first.start, WeatherDates.parse("2026-11-22T06:00:00+08:00"))
        XCTAssertEqual(first.end, WeatherDates.parse("2026-11-22T12:00:00+08:00"))
        XCTAssertEqual(first.pop, 0)
        XCTAssertEqual(first.minT, 20)
        XCTAssertEqual(first.maxT, 26)
    }

    func testPartsThatEndedAreDropped() {
        let later = WeatherDates.parse("2026-11-22T13:00:00+08:00")!
        let cells = ForecastStrip.weatherCells(weatherPeriods(), now: later)
        XCTAssertEqual(cells.first?.part, .afternoon)
        XCTAssertFalse(cells.contains { $0.end <= later })
    }

    func testNothingBeyondTwentyFourHours() {
        let cells = ForecastStrip.weatherCells(weatherPeriods(), now: now)
        let limit = now.addingTimeInterval(24 * 3600)
        XCTAssertTrue(cells.allSatisfy { $0.start < limit })
    }

    func testShortFirstPeriodSplitsAtTheBoundary() {
        // CWA's first period can start mid-period: 15:00–18:00 is one afternoon part.
        let short = period("2026-11-22T15:00:00+08:00", "2026-11-22T18:00:00+08:00")
        let night = period("2026-11-22T18:00:00+08:00", "2026-11-23T06:00:00+08:00")
        let at = WeatherDates.parse("2026-11-22T15:10:00+08:00")!
        let cells = ForecastStrip.weatherCells([night, short], now: at)
        XCTAssertEqual(cells.map(\.part), [.afternoon, .evening, .night])
        XCTAssertEqual(cells.first?.start, WeatherDates.parse("2026-11-22T15:00:00+08:00"))
    }

    func testPeriodsAreReadInTaiwanTimeNotTheDeviceZone() {
        // The same instants written in UTC: 06:00+08:00 is 22:00Z the day before.
        let utc = period("2026-11-21T22:00:00Z", "2026-11-22T10:00:00Z")
        let cells = ForecastStrip.weatherCells([utc], now: WeatherDates.parse("2026-11-22T06:30:00+08:00")!)
        XCTAssertEqual(cells.map(\.part), [.morning, .afternoon])
    }

    func testUnparseableAndEmptyPeriodsGiveNoCells() {
        XCTAssertTrue(ForecastStrip.weatherCells([], now: now).isEmpty)
        XCTAssertTrue(ForecastStrip.weatherCells([period("bad", "worse")], now: now).isEmpty)
        let backwards = period("2026-11-22T18:00:00+08:00", "2026-11-22T06:00:00+08:00")
        XCTAssertTrue(ForecastStrip.weatherCells([backwards], now: now).isEmpty)
    }

    func testOverlappingPeriodsDoNotDoubleAPart() {
        let a = period("2026-11-22T06:00:00+08:00", "2026-11-22T18:00:00+08:00", wx: 1)
        let b = period("2026-11-22T06:00:00+08:00", "2026-11-22T18:00:00+08:00", wx: 9)
        let cells = ForecastStrip.weatherCells([a, b], now: now)
        XCTAssertEqual(cells.map(\.part), [.morning, .afternoon])
    }

    // MARK: AQI trend

    private func reading(_ time: String, aqi: Double) -> HistoricalPollutant {
        HistoricalPollutant(
            aqi: aqi, pm25: 10, pm10: 10, no2: 1, so2: 1, co: 1, o3: 1,
            windDirection: 0, windSpeed: 0, publishTime: time
        )
    }

    private func forecastDay(_ day: String, aqi: Int?) -> AqiForecast {
        AqiForecast(
            area: "北部", forecastDate: day, aqi: aqi, majorPollutant: nil, minorPollutant: nil,
            minorPollutantAqi: nil, content: nil, publishTime: nil
        )
    }

    func testObservedKeepsOnlyTheLastTwelveHours() {
        let readings = (0..<24).map { hour in
            reading(String(format: "2026-11-21T%02d:00:00", hour), aqi: 50)
        } + (0...10).map { hour in
            reading(String(format: "2026-11-22T%02d:00:00", hour), aqi: 60)
        }
        let trend = ForecastStrip.aqiTrend(readings: readings, days: [], now: now)
        // 10:30 − 12 h = 22:30 yesterday: the first kept hour is 23:00.
        XCTAssertEqual(trend.observed.first?.time, Date.fromApi("2026-11-21T23:00:00"))
        XCTAssertEqual(trend.observed.last?.time, Date.fromApi("2026-11-22T10:00:00"))
        XCTAssertEqual(trend.observed.count, 12)
    }

    func testZeroReadingsAreGapsNotZeros() {
        let readings = [
            reading("2026-11-22T08:00:00", aqi: 40),
            reading("2026-11-22T09:00:00", aqi: 0),
            reading("2026-11-22T10:00:00", aqi: 55),
        ]
        let trend = ForecastStrip.aqiTrend(readings: readings, days: [], now: now)
        XCTAssertEqual(trend.observed.map(\.aqi), [40, 55])
    }

    func testForecastDaysAreClippedToNowAndTheWindow() throws {
        let days = [
            forecastDay("2026-11-22", aqi: 80),
            forecastDay("2026-11-23", aqi: 120),
            forecastDay("2026-11-24", aqi: 150),
        ]
        let trend = ForecastStrip.aqiTrend(readings: [], days: days, now: now)
        XCTAssertEqual(trend.forecast.map(\.aqi), [80, 120])

        let today = try XCTUnwrap(trend.forecast.first)
        XCTAssertEqual(today.start, now)
        XCTAssertEqual(today.end, WeatherDates.parse("2026-11-23T00:00:00+08:00"))
        let tomorrow = try XCTUnwrap(trend.forecast.last)
        XCTAssertEqual(tomorrow.start, WeatherDates.parse("2026-11-23T00:00:00+08:00"))
        XCTAssertEqual(tomorrow.end, now.addingTimeInterval(24 * 3600))
    }

    func testForecastDaysWithoutAValueAreLeftOut() {
        let days = [forecastDay("2026-11-22", aqi: nil), forecastDay("2026-11-23", aqi: 0)]
        let trend = ForecastStrip.aqiTrend(readings: [], days: days, now: now)
        XCTAssertTrue(trend.forecast.isEmpty)
        XCTAssertFalse(trend.isChartable)
    }

    func testChartableWithObservedLineOrForecastDay() {
        let line = [reading("2026-11-22T09:00:00", aqi: 40), reading("2026-11-22T10:00:00", aqi: 45)]
        XCTAssertTrue(ForecastStrip.aqiTrend(readings: line, days: [], now: now).isChartable)
        XCTAssertTrue(ForecastStrip.aqiTrend(readings: [], days: [forecastDay("2026-11-23", aqi: 70)], now: now).isChartable)
        XCTAssertFalse(ForecastStrip.aqiTrend(readings: [line[0]], days: [], now: now).isChartable)
    }

    // MARK: State

    func testStateLoadingUntilAnsweredThenEmpty() {
        let empty = ForecastStrip.aqiTrend(readings: [], days: [], now: now)
        XCTAssertEqual(ForecastStripState.make(trend: empty, cells: [], answered: false, offline: false), .loading)
        XCTAssertEqual(ForecastStripState.make(trend: empty, cells: [], answered: true, offline: false), .empty(offline: false))
        XCTAssertEqual(ForecastStripState.make(trend: empty, cells: [], answered: false, offline: true), .empty(offline: true))
    }

    func testStateLoadedWithEitherHalf() {
        let empty = ForecastStrip.aqiTrend(readings: [], days: [], now: now)
        let cells = ForecastStrip.weatherCells(weatherPeriods(), now: now)
        guard case .loaded(let trend, let shown) = ForecastStripState.make(trend: empty, cells: cells, answered: false, offline: false) else {
            return XCTFail("expected loaded")
        }
        XCTAssertNil(trend)
        XCTAssertEqual(shown, cells)
    }

    // MARK: VoiceOver

    func testAccessibilitySummaryNamesObservedForecastAndEachPart() {
        let readings = [reading("2026-11-22T09:00:00", aqi: 40), reading("2026-11-22T10:00:00", aqi: 45)]
        let trend = ForecastStrip.aqiTrend(readings: readings, days: [forecastDay("2026-11-23", aqi: 90)], now: now)
        let cells = ForecastStrip.weatherCells(weatherPeriods(), now: now)
        let text = ForecastStripView.accessibilitySummary(.loaded(trend: trend, cells: cells))
        XCTAssertTrue(text.contains("45"))
        XCTAssertTrue(text.contains("90"))
        XCTAssertGreaterThanOrEqual(text.components(separatedBy: ". ").count, 2 + cells.count)
    }

    // MARK: Review fixes

    func testAMissingHourBreaksTheObservedLine() {
        let readings = [
            reading("2026-11-22T06:00:00", aqi: 40),
            reading("2026-11-22T07:00:00", aqi: 0),
            reading("2026-11-22T08:00:00", aqi: 80),
            reading("2026-11-22T09:00:00", aqi: 82),
            reading("2026-11-22T10:00:00", aqi: 0),
        ]
        let trend = ForecastStrip.aqiTrend(readings: readings, days: [], now: now)
        // 40 stands alone; 80 and 82 are joined: no stretch from 40 to 80.
        XCTAssertEqual(trend.observedRuns.map { $0.map(\.aqi) }, [[40], [80, 82]])
    }

    func testUnbrokenHoursAreOneRun() {
        let readings = (6...10).map { reading(String(format: "2026-11-22T%02d:00:00", $0), aqi: Double($0 * 5)) }
        let trend = ForecastStrip.aqiTrend(readings: readings, days: [], now: now)
        XCTAssertEqual(trend.observedRuns.count, 1)
        XCTAssertEqual(trend.observedRuns.first?.count, 5)
        XCTAssertTrue(ForecastStrip.aqiTrend(readings: [], days: [], now: now).observedRuns.isEmpty)
    }

    func testDateLabelOnlyForLaterTaiwanDays() throws {
        let cells = ForecastStrip.weatherCells(weatherPeriods(), now: now)
        // Today's parts: no date. Tomorrow's morning (06:00 on the 23rd): "11/23".
        XCTAssertNil(ForecastStrip.dateLabel(cells[0], now: now))
        XCTAssertNil(ForecastStrip.dateLabel(cells[2], now: now))
        // The night part after midnight is already the 23rd in Taiwan.
        XCTAssertEqual(ForecastStrip.dateLabel(cells[3], now: now), "11/23")
        XCTAssertEqual(ForecastStrip.dateLabel(cells[4], now: now), "11/23")
    }

    func testDateLabelUsesTaiwanDayNotTheDeviceZone() {
        // 23:30 UTC on the 21st is 07:30 on the 22nd in Taiwan.
        let utcNow = WeatherDates.parse("2026-11-21T23:30:00Z")!
        let cell = WeatherStripCell(
            part: .morning, start: WeatherDates.parse("2026-11-22T06:00:00+08:00")!,
            end: WeatherDates.parse("2026-11-22T12:00:00+08:00")!,
            wx: 1, text: nil, pop: nil, minT: nil, maxT: nil
        )
        XCTAssertNil(ForecastStrip.dateLabel(cell, now: utcNow))
    }

    func testAccessibilitySummaryMentionsSavedData() {
        let cells = ForecastStrip.weatherCells(weatherPeriods(), now: now)
        let state = ForecastStripState.loaded(trend: nil, cells: cells)
        let plain = ForecastStripView.accessibilitySummary(state, isSaved: false, now: now)
        let saved = ForecastStripView.accessibilitySummary(state, isSaved: true, now: now)
        XCTAssertGreaterThan(saved.count, plain.count)
        XCTAssertTrue(saved.contains("Strip.saved_note".localized))
    }
}
