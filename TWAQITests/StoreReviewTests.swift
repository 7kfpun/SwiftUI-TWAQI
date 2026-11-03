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
    func testRequestsReviewEveryTwentyOpens() {
        for count in [20, 40, 60, 80, 100, 120, 1_000] {
            XCTAssertTrue(StoreReviewHelper.shouldRequestReview(appOpenCount: count), "open \(count)")
        }
    }

    func testDoesNotRequestReviewBetweenMultiplesOfTwenty() {
        for count in [1, 9, 10, 11, 19, 21, 30, 50, 99, 101, 110, 1_010] {
            XCTAssertFalse(StoreReviewHelper.shouldRequestReview(appOpenCount: count), "open \(count)")
        }
    }

    func testDoesNotRequestReviewForZeroOrNegativeCount() {
        XCTAssertFalse(StoreReviewHelper.shouldRequestReview(appOpenCount: 0))
        XCTAssertFalse(StoreReviewHelper.shouldRequestReview(appOpenCount: -20))
    }
}
