//
//  WidgetPagingTests.swift
//  TWAQITests
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest

@testable import Taiwan_Air

/// FOX-76: paging a Home Screen widget through favourites and cycling its index.
final class WidgetPagingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    /// Closest station 10, favourites 1, 2, 3.
    private let pages = WidgetPaging.pageIds(defaultId: 10, favouriteIds: [1, 2, 3])

    private func state(on stationId: Int?, tappedSecondsAgo: TimeInterval) -> WidgetPageState {
        WidgetPageState(stationId: stationId, tappedAt: now.addingTimeInterval(-tappedSecondsAgo))
    }

    // MARK: - Pages

    func testPagesStartWithTheWidgetsStationThenFavouritesInOrder() {
        XCTAssertEqual(pages, [10, 1, 2, 3])
    }

    func testWidgetsStationThatIsAFavouriteIsNotRepeated() {
        // "First favourite": the widget's station is favourite 1.
        XCTAssertEqual(WidgetPaging.pageIds(defaultId: 1, favouriteIds: [1, 2, 3]), [1, 2, 3])
        // The closest station happens to be favourite 2.
        XCTAssertEqual(WidgetPaging.pageIds(defaultId: 2, favouriteIds: [1, 2, 3, 2]), [2, 1, 3])
    }

    func testPagesWithoutAStationAreTheFavourites() {
        XCTAssertEqual(WidgetPaging.pageIds(defaultId: nil, favouriteIds: [4, 5]), [4, 5])
    }

    func testNoButtonsWithNoneOrOneFavourite() {
        XCTAssertFalse(WidgetPaging.showsPager(favouriteCount: 0, pageCount: 1))
        XCTAssertFalse(WidgetPaging.showsPager(favouriteCount: 1, pageCount: 2))
        XCTAssertTrue(WidgetPaging.showsPager(favouriteCount: 2, pageCount: 3))
        XCTAssertTrue(WidgetPaging.showsPager(favouriteCount: 2, pageCount: 2))
        // Two favourites saved, but only one with a reading to show.
        XCTAssertFalse(WidgetPaging.showsPager(favouriteCount: 2, pageCount: 1))
    }

    // MARK: - Next / previous

    func testNextAndPreviousWrap() {
        XCTAssertEqual(WidgetPaging.page(from: 0, step: 1, count: 4), 1)
        XCTAssertEqual(WidgetPaging.page(from: 3, step: 1, count: 4), 0)
        XCTAssertEqual(WidgetPaging.page(from: 0, step: -1, count: 4), 3)
        XCTAssertEqual(WidgetPaging.page(from: 2, step: -1, count: 4), 1)
        XCTAssertEqual(WidgetPaging.page(from: 0, step: 1, count: 0), 0)
    }

    func testButtonTargetsStoreNilForTheDefaultPage() {
        XCTAssertNil(WidgetPaging.target(ofPage: 0, in: pages))
        XCTAssertEqual(WidgetPaging.target(ofPage: 1, in: pages), 1)
        XCTAssertEqual(WidgetPaging.target(ofPage: 3, in: pages), 3)
        XCTAssertNil(WidgetPaging.target(ofPage: 9, in: pages))
    }

    func testSteppingThroughEveryPageComesBackToTheDefault() {
        var state = WidgetPageState()
        var shown: [Int] = []
        for _ in 0..<pages.count {
            let current = WidgetPaging.currentPage(state, pageIds: pages, now: now)
            shown.append(pages[current])
            let next = WidgetPaging.page(from: current, step: 1, count: pages.count)
            state = WidgetPaging.paged(state, to: WidgetPaging.target(ofPage: next, in: pages), now: now)
        }
        XCTAssertEqual(shown, [10, 1, 2, 3])
        XCTAssertEqual(WidgetPaging.currentPage(state, pageIds: pages, now: now), 0)
        XCTAssertNil(state.stationId)
    }

    // MARK: - Default page

    func testDefaultPageWithNothingStored() {
        XCTAssertEqual(WidgetPaging.currentPage(WidgetPageState(), pageIds: pages, now: now), 0)
    }

    func testStoredPageIsShown() {
        XCTAssertEqual(WidgetPaging.currentPage(state(on: 2, tappedSecondsAgo: 60), pageIds: pages, now: now), 2)
    }

    func testBackToDefaultAfterThirtyMinutesWithoutATap() {
        XCTAssertEqual(WidgetPaging.currentPage(state(on: 2, tappedSecondsAgo: 29 * 60), pageIds: pages, now: now), 2)
        XCTAssertEqual(WidgetPaging.currentPage(state(on: 2, tappedSecondsAgo: 30 * 60), pageIds: pages, now: now), 0)
        XCTAssertEqual(WidgetPaging.currentPage(state(on: 2, tappedSecondsAgo: 3 * 3600), pageIds: pages, now: now), 0)
    }

    func testResetDateIsThirtyMinutesAfterTheTap() {
        let paged = state(on: 2, tappedSecondsAgo: 5 * 60)
        XCTAssertEqual(WidgetPaging.resetDate(paged, pageIds: pages, now: now), now.addingTimeInterval(25 * 60))
        XCTAssertNil(WidgetPaging.resetDate(WidgetPageState(), pageIds: pages, now: now))
    }

    func testRemovedFavouriteGoesBackToDefault() {
        let paged = state(on: 2, tappedSecondsAgo: 60)
        let afterRemoval = WidgetPaging.pageIds(defaultId: 10, favouriteIds: [1, 3])
        XCTAssertEqual(WidgetPaging.currentPage(paged, pageIds: afterRemoval, now: now), 0)
        XCTAssertNil(WidgetPaging.resetDate(paged, pageIds: afterRemoval, now: now))
    }

    func testReorderedFavouritesKeepTheStationShown() {
        let paged = state(on: 2, tappedSecondsAgo: 60)
        let reordered = WidgetPaging.pageIds(defaultId: 10, favouriteIds: [3, 2, 1])
        XCTAssertEqual(reordered[WidgetPaging.currentPage(paged, pageIds: reordered, now: now)], 2)
    }

    func testRefreshGoesBackToDefaultAndKeepsTheIndex() {
        var paged = state(on: 2, tappedSecondsAgo: 60)
        paged.index = AirIndexTypes.pm25.rawValue
        let refreshed = WidgetPaging.refreshed(paged, hasNewData: true, now: now)
        XCTAssertNil(refreshed.stationId)
        XCTAssertEqual(refreshed.refreshedAt, now)
        XCTAssertEqual(refreshed.index, "pm25")
        XCTAssertEqual(WidgetPaging.currentPage(refreshed, pageIds: pages, now: now), 0)
    }

    func testRefreshWithoutNewDataKeepsThePage() {
        // Offline or a failed request: the same saved readings, so the page stays.
        let paged = state(on: 2, tappedSecondsAgo: 60)
        let refreshed = WidgetPaging.refreshed(paged, hasNewData: false, now: now)
        XCTAssertEqual(refreshed.stationId, 2)
        XCTAssertEqual(refreshed.refreshedAt, now)
        XCTAssertEqual(WidgetPaging.currentPage(refreshed, pageIds: pages, now: now), 2)
    }

    func testRefreshClearsAnExpiredPageEvenOffline() {
        // Paged to 2 at 10:10, offline since: the 11:00 refresh clears it.
        let expired = state(on: 2, tappedSecondsAgo: 50 * 60)
        let refreshed = WidgetPaging.refreshed(expired, hasNewData: false, now: now)
        XCTAssertNil(refreshed.stationId)
        XCTAssertNil(WidgetPaging.resetDate(refreshed, pageIds: pages, now: now))
    }

    func testOfflineRefreshStillPlansTheReturn() {
        // Paged at 10:10, offline refresh at 10:30: the page stays and the
        // return at 10:40 is still planned.
        let paged = state(on: 2, tappedSecondsAgo: 20 * 60)
        let refreshed = WidgetPaging.refreshed(paged, hasNewData: false, now: now)
        XCTAssertEqual(WidgetPaging.resetDate(refreshed, pageIds: pages, now: now), now.addingTimeInterval(10 * 60))
    }

    func testTapDuringTheFetchIsKept() {
        let before = state(on: nil, tappedSecondsAgo: 40 * 60)
        let tapped = WidgetPaging.paged(before, to: 3, now: now.addingTimeInterval(2))
        for hasNewData in [true, false] {
            let saved = WidgetPaging.afterFetch(tapped, readBefore: before, hasNewData: hasNewData, now: now)
            XCTAssertEqual(saved.stationId, 3)
            XCTAssertEqual(saved.tappedAt, tapped.tappedAt)
            XCTAssertEqual(saved.refreshedAt, now)
            XCTAssertEqual(WidgetPaging.currentPage(saved, pageIds: pages, now: now), 3)
        }
    }

    func testNoTapDuringTheFetchIsARefresh() {
        let before = state(on: 2, tappedSecondsAgo: 60)
        let saved = WidgetPaging.afterFetch(before, readBefore: before, hasNewData: true, now: now)
        XCTAssertEqual(saved, WidgetPaging.refreshed(before, hasNewData: true, now: now))
        XCTAssertNil(saved.stationId)
    }

    // MARK: - Tap reloads

    func testReloadRightAfterATapDrawsFromSavedReadings() {
        XCTAssertTrue(WidgetPaging.isTapReload(state(on: 1, tappedSecondsAgo: 1), now: now))
        XCTAssertFalse(WidgetPaging.isTapReload(state(on: 1, tappedSecondsAgo: 60), now: now))
        XCTAssertFalse(WidgetPaging.isTapReload(WidgetPageState(), now: now))
        // A clock that went back is not a tap reload.
        XCTAssertFalse(WidgetPaging.isTapReload(state(on: 1, tappedSecondsAgo: -30), now: now))
    }

    // MARK: - Index cycle

    func testIndexCycleOrder() {
        var index = AirIndexTypes.aqi
        var seen: [AirIndexTypes] = []
        for _ in 0..<7 {
            index = WidgetPaging.nextIndex(after: index)
            seen.append(index)
        }
        XCTAssertEqual(seen, [.pm25, .pm10, .o3, .co, .so2, .no2, .aqi])
    }

    func testEditSheetIndexIsTheStartingValue() {
        XCTAssertEqual(WidgetPaging.index(WidgetPageState(), configured: .o3), .o3)
        let cycled = WidgetPaging.cycled(WidgetPageState(), to: .no2, now: now)
        XCTAssertEqual(WidgetPaging.index(cycled, configured: .o3), .no2)
        XCTAssertEqual(cycled.tappedAt, now)
        XCTAssertEqual(WidgetPaging.index(WidgetPageState(index: "bogus"), configured: .co), .co)
    }

    func testIndexTapKeepsThePage() {
        let paged = state(on: 3, tappedSecondsAgo: 20 * 60)
        let cycled = WidgetPaging.cycled(paged, to: .pm10, now: now)
        XCTAssertEqual(WidgetPaging.currentPage(cycled, pageIds: pages, now: now), 3)
    }

    func testIndexTapDoesNotReviveAnExpiredPage() {
        let expired = state(on: 2, tappedSecondsAgo: 50 * 60)
        let cycled = WidgetPaging.cycled(expired, to: .pm25, now: now)
        XCTAssertNil(cycled.stationId)
        XCTAssertEqual(WidgetPaging.currentPage(cycled, pageIds: pages, now: now), 0)
        XCTAssertEqual(cycled.index, "pm25")
    }

    // MARK: - Keys and storage

    func testKeysDifferByFamilyAndConfiguration() {
        let keys: Set<String> = [
            WidgetPaging.key(family: "medium", station: "closest", index: "aqi"),
            WidgetPaging.key(family: "large", station: "closest", index: "aqi"),
            WidgetPaging.key(family: "medium", station: "firstFavourite", index: "aqi"),
            WidgetPaging.key(family: "medium", station: "closest", index: "pm25"),
        ]
        XCTAssertEqual(keys.count, 4)
    }

    func testStoreKeepsEachWidgetsState() throws {
        let suite = "WidgetPagingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(WidgetPageStore.state(for: "medium", in: defaults), WidgetPageState())
        let medium = state(on: 2, tappedSecondsAgo: 0)
        let large = WidgetPageState(index: "co")
        WidgetPageStore.save(medium, for: "medium", in: defaults)
        WidgetPageStore.save(large, for: "large", in: defaults)
        XCTAssertEqual(WidgetPageStore.state(for: "medium", in: defaults), medium)
        XCTAssertEqual(WidgetPageStore.state(for: "large", in: defaults), large)
        // Each widget under its own key, so concurrent writers never rewrite
        // another widget's state.
        XCTAssertNotNil(defaults.data(forKey: WidgetPageStore.defaultsKey(for: "medium")))
        XCTAssertNotNil(defaults.data(forKey: WidgetPageStore.defaultsKey(for: "large")))
        XCTAssertNotEqual(WidgetPageStore.defaultsKey(for: "medium"), WidgetPageStore.defaultsKey(for: "large"))
    }
}
