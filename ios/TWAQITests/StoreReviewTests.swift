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

    // MARK: - After feedback (FOX-80)

    func testRequestsReviewAfterFourOrFiveStarFeedback() {
        XCTAssertTrue(StoreReviewHelper.shouldRequestReview(afterFeedbackRating: 4))
        XCTAssertTrue(StoreReviewHelper.shouldRequestReview(afterFeedbackRating: 5))
    }

    func testDoesNotRequestReviewAfterOneToThreeStarFeedback() {
        for rating in [1, 2, 3] {
            XCTAssertFalse(StoreReviewHelper.shouldRequestReview(afterFeedbackRating: rating), "\(rating) stars")
        }
    }

    func testDoesNotRequestReviewForRatingsOutsideOneToFive() {
        for rating in [-1, 0, 6, 10] {
            XCTAssertFalse(StoreReviewHelper.shouldRequestReview(afterFeedbackRating: rating), "\(rating) stars")
        }
    }

    func testWriteReviewURLOpensTheAppStoreReviewPage() {
        XCTAssertEqual(
            StoreReviewHelper.writeReviewURL.absoluteString,
            "https://apps.apple.com/app/id1286516443?action=write-review"
        )
        XCTAssertTrue(StoreReviewHelper.writeReviewURL.absoluteString.hasPrefix(ShareCardSharing.appStoreURL.absoluteString))
    }

    func testReviewRequestSourceNames() {
        XCTAssertEqual(ReviewRequestSource.feedback.rawValue, "feedback")
        XCTAssertEqual(ReviewRequestSource.appOpens.rawValue, "app_opens")
    }

    func testThankYouSaysWeMayReplyOnlyWithoutTheAppStoreOffer() {
        XCTAssertEqual(
            FeedbackView.thankYouMessageKey(offersAppStoreReview: false, email: "a@b.co"),
            "Feedback.sent_message_may_reply"
        )
        XCTAssertEqual(
            FeedbackView.thankYouMessageKey(offersAppStoreReview: true, email: "a@b.co"),
            "Feedback.sent_message"
        )
        XCTAssertEqual(
            FeedbackView.thankYouMessageKey(offersAppStoreReview: false, email: "  "),
            "Feedback.sent_message"
        )
    }

    func testThankYouMessagesAreLocalized() throws {
        for language in ["en", "zh-Hant"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), language)
            let bundle = try XCTUnwrap(Bundle(path: path), language)
            for key in ["Feedback.sent_message_may_reply", "Feedback.rate_on_app_store"] {
                let value = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
                XCTAssertNotEqual(value, "MISSING", "\(language): \(key)")
            }
        }
    }
}
