//
//  StoreReviewTests.swift
//  TWAQITests
//
//  Created by kf on 3/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class StoreReviewTests: XCTestCase {
    func testRequestsReviewEveryTenOpens() {
        for count in [10, 20, 30, 40, 50, 60, 100, 110, 1_000] {
            XCTAssertTrue(StoreReviewHelper.shouldRequestReview(appOpenCount: count), "open \(count)")
        }
    }

    func testDoesNotRequestReviewBetweenMultiplesOfTen() {
        for count in [1, 2, 9, 11, 15, 19, 21, 29, 31, 99, 101, 1_001] {
            XCTAssertFalse(StoreReviewHelper.shouldRequestReview(appOpenCount: count), "open \(count)")
        }
    }

    func testDoesNotRequestReviewForZeroOrNegativeCount() {
        XCTAssertFalse(StoreReviewHelper.shouldRequestReview(appOpenCount: 0))
        XCTAssertFalse(StoreReviewHelper.shouldRequestReview(appOpenCount: -10))
    }
}
