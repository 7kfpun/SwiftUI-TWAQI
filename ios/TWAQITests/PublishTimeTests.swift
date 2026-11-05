//
//  PublishTimeTests.swift
//  TWAQITests
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest

@testable import Taiwan_Air

/// The API's `publish_time` carries no timezone and is Taiwan local time.
final class PublishTimeTests: XCTestCase {
    private let sample = "2026-08-07T22:00:00"

    // MARK: - Parsing

    func testParsesApiTimestamp() {
        XCTAssertNotNil(Date.fromApi(sample))
    }

    func testRejectsMalformedTimestamp() {
        XCTAssertNil(Date.fromApi("not a date"))
        XCTAssertNil(Date.fromApi(""))
    }

    /// An ISO string with a zone suffix is *not* the format the API sends;
    /// parsing must fail rather than silently shift the hour.
    func testRejectsTimestampWithZoneSuffix() {
        XCTAssertNil(Date.fromApi("2026-08-07T22:00:00Z"))
    }

    // MARK: - Display

    func testPublishTimeIsHoursAndMinutes() {
        XCTAssertEqual(sample.asPublishTime, "22:00")
    }

    func testUnparseableStringPassesThroughUnchanged() {
        XCTAssertEqual("garbage".asPublishTime, "garbage")
        XCTAssertEqual("garbage".asPublishDateTime, "garbage")
        XCTAssertEqual("garbage".asRelativeAge, "")
    }

    /// Regression: `asPublishDateTime` used a bare `DateFormatter`, which
    /// follows the device's calendar preference and rendered 2026 as 佛曆 2569
    /// for anyone using the Buddhist calendar. It is now pinned to Gregorian.
    ///
    /// This asserts the Gregorian year appears; on a Buddhist-calendar device
    /// the unpinned formatter produced 2569 and this would fail.
    func testPublishDateTimeUsesGregorianYear() {
        let formatted = sample.asPublishDateTime
        XCTAssertTrue(
            formatted.contains("2026"),
            "expected a Gregorian year in \(formatted)"
        )
        XCTAssertFalse(formatted.contains("2569"))
    }

    func testPublishDateTimeIncludesTheTime() {
        XCTAssertFalse(sample.asPublishDateTime.isEmpty)
        XCTAssertNotEqual(sample.asPublishDateTime, sample)
    }

    func testRelativeAgeIsNonEmptyForAValidTimestamp() {
        XCTAssertFalse(sample.asRelativeAge.isEmpty)
    }
}
