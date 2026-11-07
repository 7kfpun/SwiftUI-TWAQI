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
}
