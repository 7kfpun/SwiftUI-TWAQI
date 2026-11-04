//
//  WidgetExtraLargeTests.swift
//  TWAQITests
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import WidgetKit
import XCTest

@testable import Taiwan_Air

/// FOX-72: the extra-large widget's family rules, and how its station detail
/// keeps the last good copy of each source.
final class WidgetExtraLargeTests: XCTestCase {
    private let today = "2026-11-04"

    private let place = WidgetStationDetail.Place(
        nameLocal: "松山", lat: 25.05, lon: 121.578, county: "Taipei City", countyLocal: "臺北市",
        area: "North", areaLocal: "北部空品區"
    )

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetExtraLargeTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Family rules

    /// Every family the phone widget supports (the tests target iOS 15,
    /// before the Lock Screen ones).
    private static var allFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        if #available(iOS 16.0, *) {
            families += [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        }
        return families
    }

    func testOnlySmallMediumAndLargeListFavourites() {
        for family in Self.allFamilies {
            let expected = [.systemSmall, .systemMedium, .systemLarge].contains(family)
            XCTAssertEqual(WidgetFamilyRules.listsFavourites(family), expected, "\(family)")
        }
    }

    func testMediumLargeAndExtraLargeLockWithoutPro() {
        let pro: Set<WidgetFamily> = [.systemMedium, .systemLarge, .systemExtraLarge]
        for family in Self.allFamilies {
            XCTAssertEqual(WidgetFamilyRules.isLocked(family, isPro: false, isPreview: false), pro.contains(family), "\(family)")
            XCTAssertFalse(WidgetFamilyRules.isLocked(family, isPro: true, isPreview: false), "\(family)")
            // The gallery previews every size unlocked.
            XCTAssertFalse(WidgetFamilyRules.isLocked(family, isPro: false, isPreview: true), "\(family)")
        }
    }

    func testOnlyExtraLargeShowsStationDetail() {
        for family in Self.allFamilies {
            XCTAssertEqual(WidgetFamilyRules.showsStationDetail(family), family == .systemExtraLarge, "\(family)")
        }
    }

    // MARK: - Merge

    private func history(_ values: [Double]) -> HistoricalPollutants {
        values.map {
            HistoricalPollutant(aqi: $0, pm25: 0, pm10: 0, no2: 0, so2: 0, co: 0, o3: 0,
                                windDirection: 0, windSpeed: 0, publishTime: "")
        }
    }

    private func forecast(_ area: String, _ date: String, aqi: Int) -> AqiForecast {
        AqiForecast(area: area, forecastDate: date, aqi: aqi, majorPollutant: nil, minorPollutant: nil,
                    minorPollutantAqi: nil, content: nil, publishTime: "2026-11-04 10:30:00")
    }

    private let songshanCam = StationCam(siteId: "012", name: "松山", lat: 25.05, lon: 121.578, time: "2026-11-04T10:30:00+08:00")
    private let farCam = StationCam(siteId: "099", name: "恆春", lat: 22.0, lon: 120.7, time: nil)

    private var previous: WidgetStationDetail {
        WidgetStationDetail(
            stationId: 1, place: place, history: history([50, 60]),
            forecast: [forecast("北部", today, aqi: 40)], cam: .init(siteId: "012", time: "old")
        )
    }

    func testFailedFetchesKeepThePreviousCopy() {
        let merged = WidgetStationDetail.merged(
            previous: previous, stationId: 1, place: nil,
            history: nil, forecasts: nil, cams: nil, today: today
        )
        XCTAssertEqual(merged, previous)
    }

    func testEmptyResponsesCountAsFailed() {
        let merged = WidgetStationDetail.merged(
            previous: previous, stationId: 1, place: place,
            history: [], forecasts: [], cams: nil, today: today
        )
        XCTAssertEqual(merged.history, previous.history)
        XCTAssertEqual(merged.forecast, previous.forecast)
    }

    func testFreshFetchesReplaceThePreviousCopy() {
        let rows = [
            forecast("北部", today, aqi: 55),
            forecast("北部", "2026-11-05", aqi: 80),
            forecast("中部", today, aqi: 90),
            forecast("北部", "2026-11-03", aqi: 10), // yesterday
        ]
        let merged = WidgetStationDetail.merged(
            previous: previous, stationId: 1, place: place,
            history: history([70, 71, 72]), forecasts: rows, cams: [farCam, songshanCam], today: today
        )
        XCTAssertEqual(merged.history.map(\.aqi), [70, 71, 72])
        // The station's 空品區 only, today on.
        XCTAssertEqual(merged.forecast.map(\.aqi), [55, 80])
        XCTAssertEqual(merged.cam, .init(siteId: "012", time: "2026-11-04T10:30:00+08:00"))
    }

    func testAManifestWithoutTheStationDropsItsCam() {
        let merged = WidgetStationDetail.merged(
            previous: previous, stationId: 1, place: place,
            history: nil, forecasts: nil, cams: [farCam], today: today
        )
        XCTAssertNil(merged.cam)
    }

    func testAnAreaWithoutAForecastDropsIt() {
        let merged = WidgetStationDetail.merged(
            previous: previous, stationId: 1, place: place,
            history: nil, forecasts: [forecast("中部", today, aqi: 90)], cams: nil, today: today
        )
        XCTAssertTrue(merged.forecast.isEmpty)
        XCTAssertNil(merged.areaForecast(today: today))
    }

    func testAnotherStationsDetailIsNotReused() {
        let merged = WidgetStationDetail.merged(
            previous: previous, stationId: 2, place: nil,
            history: nil, forecasts: nil, cams: nil, today: today
        )
        XCTAssertEqual(merged, WidgetStationDetail(stationId: 2))
    }

    func testAreaForecastShowsTodayAndTomorrowOnly() {
        let detail = WidgetStationDetail(
            stationId: 1, place: place, history: [],
            forecast: [
                forecast("北部", "2026-11-03", aqi: 10),
                forecast("北部", today, aqi: 55),
                forecast("北部", "2026-11-05", aqi: 80),
                forecast("北部", "2026-11-06", aqi: 30),
            ]
        )
        XCTAssertEqual(detail.areaForecast(today: today)?.days.map(\.aqi), [55, 80])
    }

    // MARK: - Cam frame

    func testCamFrameAction() {
        let cam = WidgetStationDetail.Cam(siteId: "012", time: "t1")
        XCTAssertEqual(WidgetStationDetail.camFrameAction(previous: cam, current: nil, hasSavedFrame: true), .remove)
        XCTAssertEqual(WidgetStationDetail.camFrameAction(previous: cam, current: cam, hasSavedFrame: true), .keep)
        XCTAssertEqual(WidgetStationDetail.camFrameAction(previous: cam, current: cam, hasSavedFrame: false), .fetch)
        let newer = WidgetStationDetail.Cam(siteId: "012", time: "t2")
        XCTAssertEqual(WidgetStationDetail.camFrameAction(previous: cam, current: newer, hasSavedFrame: true), .fetch)
    }

    func testCamAfterDownload() {
        let old = WidgetStationDetail.Cam(siteId: "012", time: "t1")
        let new = WidgetStationDetail.Cam(siteId: "012", time: "t2")
        XCTAssertEqual(WidgetStationDetail.camAfterDownload(previous: old, current: new, status: 200, hasSavedFrame: true), new)
        // A 404 is a cam without a frame: the section goes, not an error.
        XCTAssertNil(WidgetStationDetail.camAfterDownload(previous: old, current: new, status: 404, hasSavedFrame: true))
        // Offline: the saved frame of the same cam stays.
        XCTAssertEqual(WidgetStationDetail.camAfterDownload(previous: old, current: new, status: nil, hasSavedFrame: true), old)
        XCTAssertNil(WidgetStationDetail.camAfterDownload(previous: old, current: new, status: nil, hasSavedFrame: false))
        let otherSite = WidgetStationDetail.Cam(siteId: "013", time: "t2")
        XCTAssertNil(WidgetStationDetail.camAfterDownload(previous: old, current: otherSite, status: 500, hasSavedFrame: true))
    }

    // MARK: - Cache

    func testCacheRoundTripsAndIgnoresAWeekOldCopy() throws {
        let cache = WidgetStationDetailCache(directory: directory)
        cache.save(previous)
        XCTAssertEqual(cache.detail(stationId: 1), previous)
        XCTAssertNil(cache.detail(stationId: 2))

        let eightDays = Date().addingTimeInterval(8 * 24 * 60 * 60)
        XCTAssertNil(cache.detail(stationId: 1, now: eightDays))
    }

    func testFrameFilesAreSavedAndRemoved() {
        let cache = WidgetStationDetailCache(directory: directory)
        XCTAssertFalse(cache.hasFrame(stationId: 1))
        cache.saveFrame(Data([0xFF, 0xD8]), stationId: 1)
        XCTAssertTrue(cache.hasFrame(stationId: 1))
        cache.removeFrame(stationId: 1)
        XCTAssertFalse(cache.hasFrame(stationId: 1))
    }

    /// The widget's cache sits where the launch purge looks.
    func testOfflinePurgeReachesTheWidgetDirectory() throws {
        let cache = WidgetStationDetailCache(directory: directory)
        cache.save(previous)
        cache.saveFrame(Data([0xFF, 0xD8]), stationId: 1)
        let appSupport = directory.appendingPathComponent("AppSupport", isDirectory: true)

        let soon = Date().addingTimeInterval(60)
        XCTAssertTrue(OfflineCacheRetention.purge(directory: appSupport, widgetDirectory: directory, now: soon).isEmpty)

        let later = Date().addingTimeInterval(OfflineCacheRetention.maxAge + 60)
        let removed = OfflineCacheRetention.purge(directory: appSupport, widgetDirectory: directory, now: later)
        XCTAssertEqual(Set(removed.map(\.lastPathComponent)), ["1.json", "1.jpg"])
        XCTAssertNil(cache.detail(stationId: 1))
    }

    // MARK: - Trend

    func testTrendThresholdFollowsTheIndex() {
        // +4 AQI points is under AQI's steady threshold of 5 …
        XCTAssertEqual(AqiTrend.from(values: [50, 50, 50, 54, 54, 54], airIndexType: .aqi)?.direction, .steady)
        // … but +40% of a PM2.5 reading is a trend.
        XCTAssertEqual(AqiTrend.from(values: [10, 10, 10, 14, 14, 14], airIndexType: .pm25)?.direction, .worsening)
    }
}
