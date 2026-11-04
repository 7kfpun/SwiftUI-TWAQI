//
//  AirQualityIntentTests.swift
//  TWAQITests
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

/// Siri / Shortcuts / Control Center (FOX-74): which station answers, the
/// station picker's entries, and what Siri says in each language.
final class AirQualityIntentTests: XCTestCase {
    private let en = Locale(identifier: "en")
    private let zh = Locale(identifier: "zh-Hant")

    private func bundle(_ identifier: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: identifier, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    private func reading(
        id: Int = 12, name: String = "Songshan", nameLocal: String = "松山",
        aqi: Double = 42, pm25: Double = 9, pm10: Double = 21, o3: Double = 31,
        publishTime: String = "2026-11-04T10:00:00"
    ) throws -> WatchReading {
        let json: [String: Any] = [
            "stationId": id, "code": name, "name": name, "nameLocal": nameLocal,
            "aqi": aqi, "pm25": pm25, "pm10": pm10, "o3": o3, "co": 0.3, "so2": 1.4, "no2": 12.5,
            "windDirection": 247, "windSpeed": 2.6, "publishTime": publishTime,
        ]
        return try JSONDecoder().decode(WatchReading.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// `hours` after the reading's 10:00 Taiwan-time publish.
    private func time(hoursAfterPublish hours: Double, of reading: WatchReading) throws -> Date {
        try XCTUnwrap(WatchStore.publishedDate(of: reading)).addingTimeInterval(hours * 60 * 60)
    }

    // MARK: - Which station answers

    func testAStationAskedForAnswersItself() {
        let resolution = StationResolution.resolve(requestedStationId: 7, favouriteIds: [3, 4], locationAvailable: false)
        XCTAssertEqual(resolution, StationResolution(plan: .station(7), note: nil))
    }

    func testNearestUsesLocationWhenTheAppHasIt() {
        let resolution = StationResolution.resolve(requestedStationId: nil, favouriteIds: [3, 4], locationAvailable: true)
        XCTAssertEqual(resolution, StationResolution(plan: .nearest, note: nil))
    }

    func testNearestWithoutLocationFallsBackToTheFirstFavouriteAndSaysSo() {
        let resolution = StationResolution.resolve(requestedStationId: nil, favouriteIds: [3, 4], locationAvailable: false)
        XCTAssertEqual(resolution, StationResolution(plan: .station(3), note: .firstFavourite))
    }

    func testNearestWithoutLocationOrFavouritesFallsBackToTheDefault() {
        let resolution = StationResolution.resolve(requestedStationId: nil, favouriteIds: [], locationAvailable: false)
        XCTAssertEqual(resolution, StationResolution(plan: .defaultLocation, note: .defaultLocation))
    }

    // MARK: - Station picker

    func testChoicesListNearestFirstThenFavouritesInTheReadersOrder() throws {
        let readings = [
            try reading(id: 4, name: "Banqiao", nameLocal: "板橋"),
            try reading(id: 3, name: "Hsinchu", nameLocal: "新竹"),
        ]
        let choices = StationChoice.choices(
            favouriteIds: [4, 3, 4, 9], readings: readings, locale: en, bundle: try bundle("en")
        )
        XCTAssertEqual(choices.map(\.id), ["nearest", "4", "3", "9"])
        XCTAssertEqual(choices.map(\.name), ["Nearest station", "Banqiao", "Hsinchu", "#9"])
        XCTAssertTrue(choices[0].isNearest)
        XCTAssertNil(choices[0].stationId)
        XCTAssertEqual(choices[1].stationId, 4)
    }

    func testChoicesAreNamedInTheAppLanguage() throws {
        let choices = StationChoice.choices(
            favouriteIds: [4], readings: [try reading(id: 4, name: "Banqiao", nameLocal: "板橋")],
            locale: zh, bundle: try bundle("zh-Hant")
        )
        XCTAssertEqual(choices.map(\.name), ["最近的測站", "板橋"])
    }

    func testChoicesWithoutFavouritesOfferNearestOnly() throws {
        let choices = StationChoice.choices(favouriteIds: [], readings: [], locale: en, bundle: try bundle("en"))
        XCTAssertEqual(choices.map(\.id), ["nearest"])
    }

    // MARK: - Answer text

    func testLiveAnswerInEnglish() throws {
        let reading = try reading()
        let text = AirQualityAnswer.text(
            reading: reading, freshness: .live, note: nil,
            now: try time(hoursAfterPublish: 0.5, of: reading), locale: en, bundle: try bundle("en")
        )
        XCTAssertEqual(text, "Songshan: AQI 42, Good. Enjoy your usual outdoor activities.")
    }

    func testLiveAnswerInChinese() throws {
        let reading = try reading()
        let text = AirQualityAnswer.text(
            reading: reading, freshness: .live, note: nil,
            now: try time(hoursAfterPublish: 0.5, of: reading), locale: zh, bundle: try bundle("zh-Hant")
        )
        XCTAssertEqual(text, "松山：AQI 42，良好。可正常從事戶外活動。")
    }

    func testAnswerNamesTheMainPollutantPastGood() throws {
        let reading = try reading(aqi: 120, pm25: 40)
        let text = AirQualityAnswer.text(
            reading: reading, freshness: .live, note: nil,
            now: try time(hoursAfterPublish: 0.5, of: reading), locale: en, bundle: try bundle("en")
        )
        XCTAssertEqual(
            text,
            "Songshan: AQI 120, Unhealthy for sensitive groups. Main pollutant: PM2.5. Consider reducing outdoor activities."
        )
    }

    func testNoReadingInBothLanguages() throws {
        XCTAssertEqual(
            AirQualityAnswer.text(reading: nil, freshness: .cached, note: nil, locale: en, bundle: try bundle("en")),
            "There's no reading yet. Open Taiwan Air once while online."
        )
        XCTAssertEqual(
            AirQualityAnswer.text(reading: nil, freshness: .cached, note: nil, locale: zh, bundle: try bundle("zh-Hant")),
            "目前還沒有數值。請在有網路時開啟 Taiwan Air 一次。"
        )
    }

    func testCachedReadingSaysHowOldItIs() throws {
        let reading = try reading()
        let now = try time(hoursAfterPublish: 3.2, of: reading)
        XCTAssertEqual(
            AirQualityAnswer.text(reading: reading, freshness: .cached, note: nil, now: now, locale: en, bundle: try bundle("en")),
            "Songshan: AQI 42, Good. Enjoy your usual outdoor activities. "
                + "You're offline, so this is the last saved reading, from 3 hours ago."
        )
        XCTAssertEqual(
            AirQualityAnswer.text(reading: reading, freshness: .cached, note: nil, now: now, locale: zh, bundle: try bundle("zh-Hant")),
            "松山：AQI 42，良好。可正常從事戶外活動。目前沒有網路，這是最後儲存的數值，為 3小時前的資料。"
        )
    }

    func testCachedReadingJustPublishedStillSaysItIsSaved() throws {
        let reading = try reading()
        let text = AirQualityAnswer.text(
            reading: reading, freshness: .cached, note: nil,
            now: try time(hoursAfterPublish: 0.25, of: reading), locale: en, bundle: try bundle("en")
        )
        XCTAssertTrue(text.hasSuffix("You're offline, so this is the last saved reading, from 15 minutes ago."), text)
    }

    func testStaleLiveReadingSaysHowOldItIs() throws {
        let reading = try reading()
        let bundle = try bundle("en")
        let fresh = AirQualityAnswer.text(
            reading: reading, freshness: .live, note: nil,
            now: try time(hoursAfterPublish: 1.9, of: reading), locale: en, bundle: bundle
        )
        XCTAssertFalse(fresh.contains("ago"), fresh)

        let stale = AirQualityAnswer.text(
            reading: reading, freshness: .live, note: nil,
            now: try time(hoursAfterPublish: 50, of: reading), locale: en, bundle: bundle
        )
        XCTAssertTrue(stale.hasSuffix("This reading is from 2 days ago."), stale)
    }

    func testFallbackIsSaidFirst() throws {
        let reading = try reading()
        let now = try time(hoursAfterPublish: 0.5, of: reading)
        XCTAssertEqual(
            AirQualityAnswer.text(reading: reading, freshness: .live, note: .firstFavourite, now: now, locale: en, bundle: try bundle("en")),
            "Taiwan Air doesn't have your location, so here is your first favourite. "
                + "Songshan: AQI 42, Good. Enjoy your usual outdoor activities."
        )
        XCTAssertEqual(
            AirQualityAnswer.text(reading: reading, freshness: .live, note: .firstFavourite, now: now, locale: zh, bundle: try bundle("zh-Hant")),
            "Taiwan Air 無法取得你的位置，以下是你的第一個最愛測站。松山：AQI 42，良好。可正常從事戶外活動。"
        )
    }

    func testAReadingWithoutAQISaysSo() throws {
        let text = AirQualityAnswer.text(
            reading: try reading(aqi: 0), freshness: .live, note: nil, locale: en, bundle: try bundle("en")
        )
        XCTAssertEqual(text, "Songshan has no AQI reading right now.")
    }

    // MARK: - Main pollutant

    func testNoMainPollutantWhileGood() throws {
        XCTAssertNil(AirQualityAnswer.mainPollutant(of: try reading(aqi: 42, pm25: 40)))
    }

    func testMainPollutantIsTheWorstBand() throws {
        XCTAssertEqual(AirQualityAnswer.mainPollutant(of: try reading(aqi: 130, pm25: 9, o3: 140)), .o3)
    }

    func testMainPollutantTiesGoToPM25First() throws {
        // PM2.5 and PM10 both moderate.
        XCTAssertEqual(AirQualityAnswer.mainPollutant(of: try reading(aqi: 60, pm25: 20, pm10: 60)), .pm25)
    }

    func testNoMainPollutantWhenEveryPollutantIsGood() throws {
        XCTAssertNil(AirQualityAnswer.mainPollutant(of: try reading(aqi: 60, pm25: 9, pm10: 21)))
    }
}
