//
//  WindTests.swift
//  TWAQITests
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI
import XCTest

@testable import Taiwan_Air

/// `wind_direction` is meteorological — degrees clockwise from north, naming
/// the direction the wind blows *from*.
final class WindTests: XCTestCase {
    // MARK: - Calm

    func testZeroSpeedIsCalm() {
        XCTAssertTrue(Wind(direction: 0, speed: 0).isCalm)
    }

    /// Stations with no anemometer report `0 / 0`, indistinguishable from
    /// genuinely still air — both must render as calm rather than "due north".
    func testMissingAnemometerReadsAsCalm() {
        XCTAssertTrue(Wind(direction: 0, speed: 0).isCalm)
        XCTAssertEqual(Wind(direction: 0, speed: 0).compassPoint, "—")
    }

    func testAnyPositiveSpeedIsNotCalm() {
        XCTAssertFalse(Wind(direction: 180, speed: 0.1).isCalm)
    }

    // MARK: - Compass points

    func testCardinalDirections() {
        XCTAssertEqual(Wind(direction: 0, speed: 2).compassPoint, "N")
        XCTAssertEqual(Wind(direction: 90, speed: 2).compassPoint, "E")
        XCTAssertEqual(Wind(direction: 180, speed: 2).compassPoint, "S")
        XCTAssertEqual(Wind(direction: 270, speed: 2).compassPoint, "W")
    }

    func testIntercardinalDirections() {
        XCTAssertEqual(Wind(direction: 45, speed: 2).compassPoint, "NE")
        XCTAssertEqual(Wind(direction: 135, speed: 2).compassPoint, "SE")
        XCTAssertEqual(Wind(direction: 225, speed: 2).compassPoint, "SW")
        XCTAssertEqual(Wind(direction: 315, speed: 2).compassPoint, "NW")
    }

    /// The reading shown in the screenshot that prompted the compass redesign.
    func testWestSouthWest() {
        XCTAssertEqual(Wind(direction: 247, speed: 2.6).compassPoint, "WSW")
    }

    func testEachOfTheSixteenPointsIsReachable() {
        let points = (0..<16).map { index in
            Wind(direction: Double(index) * 22.5, speed: 2).compassPoint
        }
        XCTAssertEqual(Set(points).count, 16, "every 22.5° step should name a distinct point")
    }

    /// 360 and 0 are the same bearing; the modulo must not index past the end.
    func testFullCircleWrapsToNorth() {
        XCTAssertEqual(Wind(direction: 360, speed: 2).compassPoint, "N")
        XCTAssertEqual(Wind(direction: 720, speed: 2).compassPoint, "N")
    }

    func testJustUnderFullCircleIsNorth() {
        XCTAssertEqual(Wind(direction: 350, speed: 2).compassPoint, "N")
    }

    func testNegativeBearingsNormalise() {
        XCTAssertEqual(Wind(direction: -90, speed: 2).compassPoint, "W")
        XCTAssertEqual(Wind(direction: -45, speed: 2).compassPoint, "NW")
    }

    // MARK: - Beaufort descriptor

    func testSpeedDescriptors() {
        XCTAssertEqual(Wind(direction: 0, speed: 0.1).toString(), "Wind.calm")
        XCTAssertEqual(Wind(direction: 0, speed: 1.0).toString(), "Wind.light_air")
        XCTAssertEqual(Wind(direction: 0, speed: 2.6).toString(), "Wind.light_breeze")
        XCTAssertEqual(Wind(direction: 0, speed: 4.0).toString(), "Wind.gentle_breeze")
        XCTAssertEqual(Wind(direction: 0, speed: 6.0).toString(), "Wind.moderate_breeze")
        XCTAssertEqual(Wind(direction: 0, speed: 20.0).toString(), "Wind.strong_breeze")
    }

    /// Each band is half-open, so the boundary value belongs to the band above.
    func testDescriptorBoundaries() {
        XCTAssertEqual(Wind(direction: 0, speed: 0.3).toString(), "Wind.light_air")
        XCTAssertEqual(Wind(direction: 0, speed: 1.6).toString(), "Wind.light_breeze")
        XCTAssertEqual(Wind(direction: 0, speed: 3.4).toString(), "Wind.gentle_breeze")
        XCTAssertEqual(Wind(direction: 0, speed: 5.5).toString(), "Wind.moderate_breeze")
        XCTAssertEqual(Wind(direction: 0, speed: 8.0).toString(), "Wind.strong_breeze")
    }

    // MARK: - Arrow

    func testArrowRotationMatchesBearing() {
        XCTAssertEqual(Wind(direction: 247, speed: 2).arrowRotation.degrees, 247, accuracy: 0.001)
    }

    // MARK: - Strength

    /// Drives the compass arrow's length and drift speed, so the bounds matter:
    /// past 1 the arrow would outgrow the ring, below 0 it would invert.
    func testCalmHasNoStrength() {
        XCTAssertEqual(Wind(direction: 0, speed: 0).strengthFraction, 0)
    }

    func testStrengthIsProportionalWithinTheNamedRange() {
        XCTAssertEqual(Wind(direction: 0, speed: 2).strengthFraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(Wind(direction: 0, speed: 4).strengthFraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(Wind(direction: 0, speed: 6).strengthFraction, 0.75, accuracy: 0.0001)
    }

    func testStrengthReachesOneAtStrongBreeze() {
        XCTAssertEqual(
            Wind(direction: 0, speed: Wind.strongBreezeThreshold).strengthFraction,
            1,
            accuracy: 0.0001
        )
    }

    /// A gale must not stretch the arrow past the compass ring.
    func testStrengthClampsAboveStrongBreeze() {
        XCTAssertEqual(Wind(direction: 0, speed: 25).strengthFraction, 1)
        XCTAssertEqual(Wind(direction: 0, speed: 200).strengthFraction, 1)
    }

    func testStrengthNeverGoesNegative() {
        XCTAssertEqual(Wind(direction: 0, speed: -5).strengthFraction, 0)
    }

    func testStrengthRisesMonotonicallyWithSpeed() {
        let speeds = [0.0, 0.5, 1.4, 2.6, 4.0, 5.5, 8.0, 12.0]
        let fractions = speeds.map { Wind(direction: 0, speed: $0).strengthFraction }

        for (lower, upper) in zip(fractions, fractions.dropFirst()) {
            XCTAssertLessThanOrEqual(lower, upper)
        }
    }
}
