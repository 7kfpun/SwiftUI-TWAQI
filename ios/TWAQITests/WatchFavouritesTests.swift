//
//  WatchFavouritesTests.swift
//  TWAQITests
//
//  Created by kf on 8/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest

@testable import Taiwan_Air

/// FOX-174: the favourites the phone sends the watch, and its pages.
final class WatchFavouritesTests: XCTestCase {
    func testContextRoundTripsIdsInOrder() {
        let context = WatchFavourites.context(for: [105, 3, 42])
        XCTAssertEqual(WatchFavourites.ids(fromContext: context), [105, 3, 42])
    }

    func testEmptyFavouritesAreSentAndReadAsEmpty() {
        let context = WatchFavourites.context(for: [])
        XCTAssertEqual(WatchFavourites.ids(fromContext: context), [])
    }

    func testContextWithoutTheKeyOrWrongTypeIsIgnored() {
        XCTAssertNil(WatchFavourites.ids(fromContext: [:]))
        XCTAssertNil(WatchFavourites.ids(fromContext: [WatchFavourites.contextKey: "1,2"]))
    }

    func testDuplicateIdsAreDropped() {
        let context = WatchFavourites.context(for: [1, 2, 1, 3, 2])
        XCTAssertEqual(WatchFavourites.ids(fromContext: context), [1, 2, 3])
    }

    func testPagesAreTheFavouritesWhenTheCurrentStationIsOne() {
        XCTAssertEqual(WatchFavourites.pages(favourites: [1, 2, 3], current: 2), [1, 2, 3])
    }

    func testPagesLeadWithACurrentStationThatIsNotAFavourite() {
        XCTAssertEqual(WatchFavourites.pages(favourites: [1, 2], current: 9), [9, 1, 2])
    }

    func testPagesWithoutACurrentStationAreTheFavourites() {
        XCTAssertEqual(WatchFavourites.pages(favourites: [1, 2], current: nil), [1, 2])
    }

    func testNoFavouritesMeansNoPager() {
        XCTAssertLessThan(WatchFavourites.pages(favourites: [], current: 9).count, 2)
        XCTAssertLessThan(WatchFavourites.pages(favourites: [], current: nil).count, 2)
    }

    func testOneFavouriteThatIsOnScreenMeansNoPager() {
        XCTAssertLessThan(WatchFavourites.pages(favourites: [5], current: 5).count, 2)
    }
}
