//
//  ForecastTabOrderingTests.swift
//  TWAQITests
//
//  Created by kf on 3/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

/// FOX-32: the Forecast tab lists every 空品區 — the reader's area, then the
/// favourites' areas, then the rest — each with every day the feed returns.
final class ForecastTabOrderingTests: XCTestCase {
    private let today = "2026-11-03"

    private func row(
        _ area: String,
        _ date: String,
        aqi: Int? = 50,
        content: String? = nil,
        published: String = "2026-11-03 10:30:00"
    ) -> AqiForecast {
        AqiForecast(
            area: area, forecastDate: date, aqi: aqi, majorPollutant: nil, minorPollutant: nil,
            minorPollutantAqi: nil, content: content, publishTime: published
        )
    }

    /// Every area for today, in an order that isn't MOENV's.
    private var allAreas: [AqiForecast] {
        ["馬祖", "高屏", "北部", "金門", "竹苗", "花東", "中部", "澎湖", "宜蘭", "雲嘉南"].map { row($0, today) }
    }

    private func order(
        _ forecasts: [AqiForecast],
        reader: String? = nil,
        favourites: [String?] = [],
        chinese: Bool = true
    ) -> [ForecastTabArea] {
        ForecastTabOrdering.areas(
            forecasts: forecasts, readerArea: reader, favouriteAreas: favourites, today: today, chinese: chinese
        )
    }

    // MARK: - Order

    func testReaderAreaFirstThenFavouritesThenRestInRegionOrder() {
        let result = order(allAreas, reader: "高屏", favourites: ["宜蘭", "中部"])

        XCTAssertEqual(result.map(\.area), ["高屏", "宜蘭", "中部", "北部", "竹苗", "雲嘉南", "花東", "澎湖", "金門", "馬祖"])
        XCTAssertEqual(result.map(\.pin), [.reader, .favourite, .favourite] + Array(repeating: .none, count: 7))
    }

    func testNoLocationPinsNorthAsTheFallback() {
        let result = order(allAreas, reader: nil, favourites: ["花東"])

        XCTAssertEqual(result.prefix(2).map(\.area), ["北部", "花東"])
        XCTAssertEqual(result.prefix(2).map(\.pin), [.fallback, .favourite])
        XCTAssertEqual(result.count, 10, "Every area is listed")
    }

    func testReaderAreaWithoutAForecastFallsBackToNorth() {
        let forecasts = allAreas.filter { $0.area != "澎湖" }

        let result = order(forecasts, reader: "澎湖")

        XCTAssertEqual(result.first?.area, "北部")
        XCTAssertEqual(result.first?.pin, .fallback)
        XCTAssertFalse(result.map(\.area).contains("澎湖"))
    }

    func testFavouriteInReaderAreaStaysPinnedAsReaderAndAppearsOnce() {
        let result = order(allAreas, reader: "北部", favourites: ["北部", nil, "竹苗", "竹苗"])

        XCTAssertEqual(result.prefix(2).map(\.area), ["北部", "竹苗"])
        XCTAssertEqual(result.prefix(2).map(\.pin), [.reader, .favourite])
        XCTAssertEqual(result.count, Set(result.map(\.area)).count, "No area twice")
    }

    func testFavouritesKeepFavouritesOrder() {
        let result = order(allAreas, reader: "北部", favourites: ["馬祖", "雲嘉南", "竹苗"])

        XCTAssertEqual(result.prefix(4).map(\.area), ["北部", "馬祖", "雲嘉南", "竹苗"])
    }

    func testFavouriteAreaWithoutAForecastIsSkipped() {
        let forecasts = allAreas.filter { $0.area != "金門" }

        let result = order(forecasts, reader: "北部", favourites: ["金門", "中部"])

        XCTAssertEqual(result.prefix(2).map(\.area), ["北部", "中部"])
    }

    func testAreaOutsideTheKnownListGoesLast() {
        let result = order(allAreas + [row("東沙", today)], reader: "北部")

        XCTAssertEqual(result.last?.area, "東沙")
    }

    // MARK: - Days

    func testEveryDayTheFeedReturnsIsKeptNotJustThree() {
        let dates = ["2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07"]
        let forecasts = dates.map { row("北部", $0) }

        let result = order(forecasts)

        XCTAssertEqual(result.first?.forecast.days.map(\.forecastDate), dates)
    }

    func testDaysBeforeTodayAreDroppedAndAnAreaWithOnlyPastDaysIsLeftOut() {
        let forecasts = [
            row("北部", "2026-11-02"), row("北部", "2026-11-04"), row("北部", today),
            row("中部", "2026-11-01"),
        ]

        let result = order(forecasts)

        XCTAssertEqual(result.map(\.area), ["北部"])
        XCTAssertEqual(result.first?.forecast.days.map(\.forecastDate), [today, "2026-11-04"])
    }

    func testTwoRowsForOneDayKeepTheNewestPublish() {
        let forecasts = [
            row("北部", today, aqi: 40, published: "2026-11-02 16:30:00"),
            row("北部", today, aqi: 70, published: "2026-11-03 10:30:00"),
        ]

        XCTAssertEqual(order(forecasts).first?.forecast.days.map(\.aqi), [70])
    }

    func testNoForecastsGivesNoAreas() {
        XCTAssertTrue(order([], reader: "北部", favourites: ["中部"]).isEmpty)
    }

    // MARK: - Titles and shared text

    func testTitlesInChineseAndEnglish() {
        XCTAssertEqual(ForecastTabOrdering.title("北部", chinese: true), "北部空品區")
        XCTAssertEqual(ForecastTabOrdering.title("雲嘉南", chinese: true), "雲嘉南空品區")
        XCTAssertEqual(ForecastTabOrdering.title("金門", chinese: true), "金門")
        XCTAssertEqual(ForecastTabOrdering.title("北部", chinese: false), "North")
        XCTAssertEqual(ForecastTabOrdering.title("馬祖", chinese: false), "Matsu")
        XCTAssertEqual(ForecastTabOrdering.title("東沙", chinese: false), "東沙")

        XCTAssertEqual(order(allAreas, chinese: false).first?.forecast.areaTitle, "North")
    }

    func testSharedContentWhenEveryAreaRepeatsOneParagraph() {
        let text = "1. 今日各地擴散條件良好。"
        let result = order([row("北部", today, content: text), row("中部", today, content: text), row("花東", today)])

        XCTAssertEqual(ForecastTabOrdering.sharedContent(result), text)
    }

    func testNoSharedContentWhenAreasDiffer() {
        let result = order([row("北部", today, content: "北部普通。"), row("中部", today, content: "中部良好。")])

        XCTAssertNil(ForecastTabOrdering.sharedContent(result))
    }

    func testNoSharedContentForASingleArea() {
        XCTAssertNil(ForecastTabOrdering.sharedContent(order([row("北部", today, content: "北部普通。")])))
    }
}
