//
//  WidgetStationChoiceTests.swift
//  TWAQITests
//
//  FOX-137: the Home Screen widget can show a chosen station.
//

import XCTest
@testable import Taiwan_Air

final class WidgetStationChoiceTests: XCTestCase {
    private let all = [
        StationDirectoryEntry(id: 1, name: "Zhongzheng", nameLocal: "中正", code: "A1"),
        StationDirectoryEntry(id: 2, name: "Taipei Main", nameLocal: "臺北", code: "A2"),
        StationDirectoryEntry(id: 3, name: "Kaohsiung", nameLocal: "高雄", code: "B3"),
    ]

    func testLeadingIdByMode() {
        XCTAssertNil(WidgetStationChoice.leadingId(mode: .closest, chosenId: 3, firstFavouriteId: 2))
        XCTAssertEqual(WidgetStationChoice.leadingId(mode: .firstFavourite, chosenId: 3, firstFavouriteId: 2), 2)
        XCTAssertEqual(WidgetStationChoice.leadingId(mode: .station, chosenId: 3, firstFavouriteId: 2), 3)
    }

    func testMissingStationFallsBackToClosest() {
        XCTAssertNil(WidgetStationChoice.leadingId(mode: .station, chosenId: nil, firstFavouriteId: 2))
        XCTAssertNil(WidgetStationChoice.leadingId(mode: .firstFavourite, chosenId: 3, firstFavouriteId: nil))
    }

    func testGoneOnlyWhenTheRequestSucceededWithoutTheStation() {
        XCTAssertTrue(WidgetStationChoice.isGone(chosenId: 9, fetchedIds: [1, 2], fetchSucceeded: true))
        XCTAssertTrue(WidgetStationChoice.isGone(chosenId: 9, fetchedIds: [], fetchSucceeded: true))
        XCTAssertFalse(WidgetStationChoice.isGone(chosenId: 2, fetchedIds: [1, 2], fetchSucceeded: true))
        // Offline: keep the last reading rather than switching stations.
        XCTAssertFalse(WidgetStationChoice.isGone(chosenId: 9, fetchedIds: [], fetchSucceeded: false))
    }

    func testKeyPartSeparatesChosenStations() {
        XCTAssertEqual(WidgetStationChoice.keyPart(mode: .closest, chosenId: 3), "closest")
        XCTAssertEqual(WidgetStationChoice.keyPart(mode: .station, chosenId: 3), "station-3")
        XCTAssertEqual(WidgetStationChoice.keyPart(mode: .station, chosenId: nil), "station-none")
    }

    func testSearchMatchesNamesAndCodeIgnoringCaseAndVariants() {
        XCTAssertEqual(StationDirectoryEntry.search("kaoh", in: all, favouriteIds: []).map(\.id), [3])
        XCTAssertEqual(StationDirectoryEntry.search("高", in: all, favouriteIds: []).map(\.id), [3])
        XCTAssertEqual(StationDirectoryEntry.search("a2", in: all, favouriteIds: []).map(\.id), [2])
        // 台 finds 臺.
        XCTAssertEqual(StationDirectoryEntry.search("台北", in: all, favouriteIds: []).map(\.id), [2])
        XCTAssertTrue(StationDirectoryEntry.search("nowhere", in: all, favouriteIds: []).isEmpty)
    }

    func testBlankSearchListsFavouritesFirstInTheirOrder() {
        XCTAssertEqual(StationDirectoryEntry.search(" ", in: all, favouriteIds: [3, 1]).map(\.id), [3, 1, 2])
    }

    func testDisplayNameFollowsLanguageAndNeverBlank() {
        let zh = Locale(identifier: "zh-Hant")
        let en = Locale(identifier: "en")
        XCTAssertEqual(all[0].displayName(locale: zh), "中正")
        XCTAssertEqual(all[0].displayName(locale: en), "Zhongzheng")
        XCTAssertEqual(StationDirectoryEntry(id: 7, name: "", nameLocal: "", code: "C7").displayName(locale: en), "C7")
        XCTAssertEqual(StationDirectoryEntry(id: 7, name: "", nameLocal: "", code: "").displayName(locale: en), "#7")
    }

    // MARK: Gone-station response and chosen-station cache

    func testNoSuchStationBodyIsASuccessWithNoStations() throws {
        let body = Data(#"{"success":false,"error":"No such a station"}"#.utf8)
        XCTAssertEqual(try WatchAPI.decodeStations(body).count, 0)
    }

    func testOtherErrorBodiesStillFail() {
        for error in ["Too many station ids", "boom"] {
            let body = Data(#"{"success":false,"error":"\#(error)"}"#.utf8)
            XCTAssertThrowsError(try WatchAPI.decodeStations(body))
        }
        XCTAssertThrowsError(try WatchAPI.decodeStations(Data("nope".utf8)))
    }

    private func reading(_ id: Int, publishTime: String) -> WatchReading {
        let json: [String: Any] = [
            "stationId": id, "code": "S\(id)", "name": "Station", "nameLocal": "測站",
            "aqi": 50, "pm25": 10, "pm10": 20, "o3": 30, "co": 0.3, "so2": 1, "no2": 10,
            "windDirection": 0, "windSpeed": 1, "publishTime": publishTime,
        ]
        return try! JSONDecoder().decode(WatchReading.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func recent(minutesAgo: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        return formatter.string(from: Date().addingTimeInterval(TimeInterval(-minutesAgo * 60)))
    }

    func testChosenCacheKeepsNewestEightAndReplacesByStation() {
        let savedChosen = WatchStore.chosenReadings
        let savedFavourites = WatchStore.favouriteReadings
        defer {
            WatchStore.chosenReadings = savedChosen
            WatchStore.favouriteReadings = savedFavourites
        }
        WatchStore.chosenReadings = []
        for id in 1...9 { WatchStore.cacheChosenReading(reading(id, publishTime: recent(minutesAgo: 30))) }
        XCTAssertEqual(WatchStore.chosenReadings.map(\.stationId), Array(2...9))

        WatchStore.cacheChosenReading(reading(5, publishTime: recent(minutesAgo: 5)))
        XCTAssertEqual(WatchStore.chosenReadings.count, 8)
        XCTAssertEqual(WatchStore.chosenReadings.last?.stationId, 5)
    }

    func testCachedReadingPrefersNewerCopyAndDropForgetsBoth() {
        let savedChosen = WatchStore.chosenReadings
        let savedFavourites = WatchStore.favouriteReadings
        defer {
            WatchStore.chosenReadings = savedChosen
            WatchStore.favouriteReadings = savedFavourites
        }
        let older = reading(7, publishTime: recent(minutesAgo: 60))
        let newer = reading(7, publishTime: recent(minutesAgo: 10))
        WatchStore.favouriteReadings = [older]
        WatchStore.chosenReadings = [newer]
        XCTAssertEqual(WatchStore.cachedReading(stationId: 7), newer)
        WatchStore.favouriteReadings = [newer]
        WatchStore.chosenReadings = [older]
        XCTAssertEqual(WatchStore.cachedReading(stationId: 7), newer)

        WatchStore.dropReading(stationId: 7)
        XCTAssertNil(WatchStore.cachedReading(stationId: 7))
    }
}
