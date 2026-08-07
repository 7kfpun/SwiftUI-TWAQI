//
//  AqiTrendTests.swift
//  TWAQITests
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class AqiTrendTests: XCTestCase {

    // MARK: - Not enough history

    func testNoReadingsHasNoTrend() {
        XCTAssertNil(AqiTrend.from(values: []))
    }

    func testSingleReadingHasNoTrend() {
        XCTAssertNil(AqiTrend.from(values: [65]))
    }

    // MARK: - Direction

    func testFallingAqiIsImproving() {
        // Oldest first: 12 hours drifting down from ~90 to ~50.
        let values: [Double] = [90, 88, 86, 84, 80, 76, 70, 64, 60, 56, 52, 50]
        let trend = AqiTrend.from(values: values)

        XCTAssertEqual(trend?.direction, .improving)
        XCTAssertGreaterThan(trend?.change ?? 0, 0)
    }

    func testRisingAqiIsWorsening() {
        let values: [Double] = [50, 52, 56, 60, 64, 70, 76, 80, 84, 86, 88, 90]
        let trend = AqiTrend.from(values: values)

        XCTAssertEqual(trend?.direction, .worsening)
        XCTAssertGreaterThan(trend?.change ?? 0, 0)
    }

    func testFlatAqiIsSteady() {
        let values = [Double](repeating: 65, count: 12)
        let trend = AqiTrend.from(values: values)

        XCTAssertEqual(trend?.direction, .steady)
        XCTAssertEqual(trend?.change, 0)
    }

    /// Movement smaller than the threshold is noise and must not be reported as
    /// a direction — otherwise every station permanently reads "getting worse".
    func testMovementBelowThresholdIsSteady() {
        let values: [Double] = [60, 60, 60, 61, 61, 61, 62, 62, 62, 63, 63, 63]
        let trend = AqiTrend.from(values: values)

        XCTAssertEqual(trend?.direction, .steady)
    }

    func testMovementAtThresholdIsNotSteady() {
        // Earlier window averages 60, recent window averages 66 — a 6 point
        // move, just past the 5 point steady band.
        let values: [Double] = [60, 60, 60, 60, 60, 60, 60, 60, 60, 66, 66, 66]
        let trend = AqiTrend.from(values: values)

        XCTAssertEqual(trend?.direction, .worsening)
        XCTAssertEqual(trend?.change, 6)
    }

    // MARK: - Spike resistance

    /// The reason both ends are averaged. A single bad hour in the middle of an
    /// otherwise improving day must not flip the verdict to "getting worse".
    func testSingleSpikeDoesNotFlipDirection() {
        var values: [Double] = [90, 88, 86, 84, 80, 76, 70, 64, 60, 56, 52, 50]
        values[8] = 150 // one hour of smoke

        XCTAssertEqual(AqiTrend.from(values: values)?.direction, .improving)
    }

    /// A spike as the newest reading is real and should register.
    func testSustainedRiseAtTheEndIsWorsening() {
        let values: [Double] = [50, 50, 50, 50, 50, 50, 50, 50, 50, 120, 130, 140]

        XCTAssertEqual(AqiTrend.from(values: values)?.direction, .worsening)
    }

    // MARK: - Reported values

    func testCurrentIsMeanOfMostRecentWindow() {
        let values: [Double] = [10, 10, 10, 10, 10, 10, 10, 10, 10, 30, 40, 50]
        // Most recent three are 30, 40, 50.
        XCTAssertEqual(AqiTrend.from(values: values)?.current ?? 0, 40, accuracy: 0.001)
    }

    func testChangeIsAbsoluteSoDirectionCarriesTheSign() {
        let falling: [Double] = [80, 80, 80, 80, 80, 80, 80, 80, 80, 40, 40, 40]
        let rising: [Double] = [40, 40, 40, 40, 40, 40, 40, 40, 40, 80, 80, 80]

        XCTAssertEqual(AqiTrend.from(values: falling)?.change, 40)
        XCTAssertEqual(AqiTrend.from(values: rising)?.change, 40)
    }

    /// With fewer than nine readings there is no six-hour look-back, so it falls
    /// back to comparing against the oldest three.
    func testShortSeriesFallsBackToOldestReadings() {
        let values: [Double] = [100, 100, 100, 50, 50, 50]
        let trend = AqiTrend.from(values: values)

        XCTAssertEqual(trend?.direction, .improving)
        XCTAssertEqual(trend?.change, 50)
    }

    func testTwoReadingsProduceATrend() {
        XCTAssertNotNil(AqiTrend.from(values: [100, 40]))
    }
}
