//
//  AirStatusesTests.swift
//  TWAQITests
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

/// Band boundaries drive the colour of every marker, badge and chart bar, so an
/// off-by-one here is visible everywhere at once.
final class AirStatusesTests: XCTestCase {

    private func aqi(_ value: Double) -> AirStatuses {
        AirStatuses.checkAirStatus(airIndexType: .aqi, value: value)
    }

    // MARK: - AQI bands

    func testAqiBandMidpoints() {
        XCTAssertEqual(aqi(25), .good)
        XCTAssertEqual(aqi(75), .moderate)
        XCTAssertEqual(aqi(125), .unhealthyforsensitivegroup)
        XCTAssertEqual(aqi(175), .unhealthy)
        XCTAssertEqual(aqi(250), .veryunhealthy)
        XCTAssertEqual(aqi(400), .hazardous)
    }

    /// The exact edges — each boundary belongs to the higher band.
    func testAqiBandBoundaries() {
        XCTAssertEqual(aqi(50), .good)
        XCTAssertEqual(aqi(51), .moderate)
        XCTAssertEqual(aqi(100), .moderate)
        XCTAssertEqual(aqi(101), .unhealthyforsensitivegroup)
        XCTAssertEqual(aqi(150), .unhealthyforsensitivegroup)
        XCTAssertEqual(aqi(151), .unhealthy)
        XCTAssertEqual(aqi(200), .unhealthy)
        XCTAssertEqual(aqi(201), .veryunhealthy)
        XCTAssertEqual(aqi(300), .veryunhealthy)
        XCTAssertEqual(aqi(301), .hazardous)
    }

    /// Zero means "no reading", not "perfect air" — several stations report 0.0
    /// for pollutants they do not measure.
    func testZeroIsUnknownRatherThanGood() {
        XCTAssertEqual(aqi(0), .unknown)
    }

    func testNegativeIsUnknown() {
        XCTAssertEqual(aqi(-5), .unknown)
    }

    // MARK: - Face images

    /// Regression: the unknown status has no artwork, and asking for it by name
    /// logged "No image named 'status_unknown'" on every render.
    func testUnknownStatusHasNoFaceImage() {
        XCTAssertFalse(AirStatuses.unknown.hasFaceImage)
    }

    func testRealStatusesHaveFaceImages() {
        for status in AirStatuses.getShowAllCases() {
            XCTAssertTrue(
                status.hasFaceImage,
                "\(status) is shown in the legend so it needs artwork"
            )
        }
    }

    // MARK: - Legend

    /// The legend shows the six real bands and never "unknown".
    func testLegendExcludesUnknown() {
        XCTAssertFalse(AirStatuses.getShowAllCases().contains(.unknown))
        XCTAssertEqual(AirStatuses.getShowAllCases().count, 6)
    }

    // MARK: - PM2.5

    func testPm25Bands() {
        func pm25(_ value: Double) -> AirStatuses {
            AirStatuses.checkAirStatus(airIndexType: .pm25, value: value)
        }

        XCTAssertEqual(pm25(10), .good)
        XCTAssertEqual(pm25(20), .moderate)
        XCTAssertEqual(pm25(40), .unhealthyforsensitivegroup)
        XCTAssertEqual(pm25(100), .unhealthy)
        XCTAssertEqual(pm25(200), .veryunhealthy)
        XCTAssertEqual(pm25(300), .hazardous)
    }
}
