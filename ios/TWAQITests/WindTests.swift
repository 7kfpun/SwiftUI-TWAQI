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

// MARK: - Wind arrows layer (TWAQ-15)

final class WindLayerTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-05T04:40:00Z")! // 12:40 Taiwan

    private func station(
        _ id: String, lat: Double = 25.01, lon: Double = 121.51,
        time: String = "2026-11-05T12:30:00+08:00", wind: String = "3.2", dir: String = "45"
    ) -> String {
        """
        { "id": "\(id)", "name": "臺北", "county": "臺北市", "lat": \(lat), "lon": \(lon), "time": "\(time)",
          "temp": 24, "humidity": 70, "rain": 0, "wind": \(wind), "windDir": \(dir) }
        """
    }

    private func file(_ stations: [String]) throws -> WeatherFile {
        let json = """
        { "updatedAt": "2026-11-05T04:40:00.000Z", "forecast": null,
          "observations": { "stations": [\(stations.joined(separator: ","))] } }
        """
        return try JSONDecoder().decode(WeatherFile.self, from: Data(json.utf8))
    }

    // MARK: Direction

    func testCompassIndexMapsBearingsToEightPoints() {
        XCTAssertEqual(WindLayer.compassIndex(0), 0)
        XCTAssertEqual(WindLayer.compassIndex(22), 0)
        XCTAssertEqual(WindLayer.compassIndex(23), 1)
        XCTAssertEqual(WindLayer.compassIndex(45), 1)
        XCTAssertEqual(WindLayer.compassIndex(90), 2)
        XCTAssertEqual(WindLayer.compassIndex(180), 4)
        XCTAssertEqual(WindLayer.compassIndex(225), 5)
        XCTAssertEqual(WindLayer.compassIndex(315), 7)
        XCTAssertEqual(WindLayer.compassIndex(338), 0)
        XCTAssertEqual(WindLayer.compassIndex(360), 0)
        XCTAssertEqual(WindLayer.compassIndex(-45), 7)
    }

    func testBearingAndAngle() {
        XCTAssertEqual(WindLayer.bearing(fromLat: 25, fromLon: 121.5, toLat: 25.1, toLon: 121.5), 0, accuracy: 0.01)
        XCTAssertEqual(WindLayer.bearing(fromLat: 25, fromLon: 121.5, toLat: 25, toLon: 121.6), 90, accuracy: 0.5)
        XCTAssertEqual(WindLayer.bearing(fromLat: 25, fromLon: 121.5, toLat: 24.9, toLon: 121.5), 180, accuracy: 0.01)
        XCTAssertEqual(WindLayer.angleBetween(350, 10), 20)
        XCTAssertEqual(WindLayer.angleBetween(10, 350), 20)
        XCTAssertEqual(WindLayer.angleBetween(0, 180), 180)
    }

    /// The arrow is drawn pointing south and rotated by the bearing the wind
    /// comes from, so it points downwind.
    func testArrowRotationIsTheBearingTheWindComesFrom() throws {
        let readings = try WindLayer.readings(in: file([station("A", dir: "45")]), now: now)
        XCTAssertEqual(readings.first?.direction, 45)
        XCTAssertEqual(readings.first?.wind.arrowRotation, .degrees(45))
        // 360 is north.
        let north = try WindLayer.readings(in: file([station("A", dir: "360")]), now: now)
        XCTAssertEqual(north.first?.direction, 0)
    }

    // MARK: Speed

    func testSpeedBandsAndStrength() {
        XCTAssertEqual(WindLayer.color(speed: 1.0), 0x8FD3F4)
        XCTAssertEqual(WindLayer.color(speed: 1.6), 0x32ADE6)
        XCTAssertEqual(WindLayer.color(speed: 3.4), 0x0A84FF)
        XCTAssertEqual(WindLayer.color(speed: 5.5), 0x5E5CE6)
        XCTAssertEqual(WindLayer.color(speed: 8), 0x8E3FD6)
        XCTAssertEqual(Wind(direction: 0, speed: 4).strengthFraction, 0.5)
        XCTAssertEqual(Wind(direction: 0, speed: 20).strengthFraction, 1)
    }

    // MARK: Readings

    func testReadingsKeepFreshStationsWithDirectionAndSpeedStrongestFirst() throws {
        let file = try file([
            station("slow", wind: "1.0"),
            station("fast", wind: "6.0"),
            station("calm", wind: "0"),
            station("nodir", dir: "null"),
            station("badir", dir: "-99"),
            station("nowind", wind: "null"),
            station("stale", time: "2026-11-05T07:00:00+08:00"),
        ])
        XCTAssertEqual(WindLayer.readings(in: file, now: now).map(\.stationId), ["fast", "slow"])
    }

    func testFileWithoutWindDirectionDecodes() throws {
        let json = """
        { "updatedAt": "x", "observations": { "stations": [
          { "id": "1", "name": "n", "lat": 25, "lon": 121.5, "time": "2026-11-05T12:30:00+08:00", "wind": 3 } ] } }
        """
        let file = try JSONDecoder().decode(WeatherFile.self, from: Data(json.utf8))
        XCTAssertTrue(WindLayer.readings(in: file, now: now).isEmpty)
    }

    // MARK: Zoom and count

    private func grid(_ n: Int) -> [WindReading] {
        (0..<n).map { i in
            WindReading(stationId: "\(i)", name: "s", lat: 22 + Double(i % 10) * 0.3,
                        lon: 120 + Double(i / 10) * 0.3, speed: 2, direction: 90)
        }
    }

    func testMarkerCountIsCappedAndGrowsWithZoom() {
        let readings = grid(100)
        func count(_ zoom: Double) -> Int {
            WindLayer.visible(readings, minLat: 21, maxLat: 26, minLon: 119, maxLon: 123, zoom: zoom).count
        }
        XCTAssertLessThanOrEqual(count(14), WindLayer.maxMarkers)
        XCTAssertEqual(count(14), WindLayer.maxMarkers)
        XCTAssertLessThan(count(6), count(9))
        XCTAssertGreaterThan(count(6), 0)
    }

    func testCrowdedCellKeepsTheStrongestAndOffscreenIsDropped() {
        let strong = WindReading(stationId: "strong", name: "", lat: 25.0, lon: 121.5, speed: 7, direction: 0)
        let weak = WindReading(stationId: "weak", name: "", lat: 25.01, lon: 121.51, speed: 2, direction: 0)
        let far = WindReading(stationId: "far", name: "", lat: 22.0, lon: 120.0, speed: 9, direction: 0)
        let shown = WindLayer.visible([far, strong, weak].sorted { $0.speed > $1.speed },
                                      minLat: 24.9, maxLat: 25.1, minLon: 121.4, maxLon: 121.6, zoom: 7)
        XCTAssertEqual(shown.map(\.stationId), ["strong"])
    }

    // MARK: Hint

    private let centre = (lat: 25.0, lon: 121.5)
    private let northEast = [(lat: 25.1, lon: 121.6, pm25: 40.0), (lat: 25.08, lon: 121.58, pm25: 36.0)]

    func testHintNamesWhereTheAirComesFrom() throws {
        let file = try file([station("A", dir: "45")])
        let hint = WindLayer.hint(lat: centre.lat, lon: centre.lon, localPm25: 20, stations: northEast, in: file, now: now)
        XCTAssertEqual(hint, WindLayer.Hint(fromIndex: 1, trend: .higher))

        let cleaner = [(lat: 25.1, lon: 121.6, pm25: 8.0), (lat: 25.08, lon: 121.58, pm25: 6.0)]
        XCTAssertEqual(
            WindLayer.hint(lat: centre.lat, lon: centre.lon, localPm25: 20, stations: cleaner, in: file, now: now),
            WindLayer.Hint(fromIndex: 1, trend: .lower)
        )
    }

    func testNoHintWhenNotClear() throws {
        let hint = { (file: WeatherFile, stations: [(lat: Double, lon: Double, pm25: Double)], local: Double) in
            WindLayer.hint(lat: self.centre.lat, lon: self.centre.lon, localPm25: local, stations: stations, in: file, now: self.now)
        }
        let ne = try file([station("A", dir: "45")])
        XCTAssertNotNil(hint(ne, northEast, 20))
        // Light wind, stale reading, differences too small, one station only, stations downwind.
        XCTAssertNil(hint(try file([station("A", wind: "1.0", dir: "45")]), northEast, 20))
        XCTAssertNil(hint(try file([station("A", time: "2026-11-05T07:00:00+08:00")]), northEast, 20))
        XCTAssertNil(hint(ne, northEast, 33))
        XCTAssertNil(hint(ne, Array(northEast.prefix(1)), 20))
        XCTAssertNil(hint(try file([station("A", dir: "225")]), northEast, 20))
        // No local reading, no wind station near.
        XCTAssertNil(hint(ne, northEast, 0))
        XCTAssertNil(hint(try file([station("A", lat: 23.0, lon: 120.0)]), northEast, 20))
    }

    /// A calm station on top of the centre doesn't hide a windier one further
    /// out (within range): the hint reads the nearest station that has wind.
    func testHintSkipsACalmStationNextToTheCentre() throws {
        let file = try file([
            station("calm", lat: 25.001, lon: 121.501, wind: "0.4", dir: "225"),
            station("windy", lat: 25.05, lon: 121.55, wind: "3.0", dir: "45"),
        ])
        XCTAssertEqual(
            WindLayer.hint(lat: centre.lat, lon: centre.lon, localPm25: 20, stations: northEast, in: file, now: now),
            WindLayer.Hint(fromIndex: 1, trend: .higher)
        )
    }

    // MARK: Words

    private func lproj(_ identifier: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: identifier, ofType: "lproj"), identifier)
        return try XCTUnwrap(Bundle(path: path), identifier)
    }

    func testHintAndVoiceOverTextInBothLanguages() throws {
        let en = try lproj("en"), zh = try lproj("zh-Hant")
        let hint = WindLayer.Hint(fromIndex: 1, trend: .higher)
        XCTAssertEqual(WindLayer.hintText(hint, bundle: en), "Air is coming from the north-east, where PM2.5 is higher")
        XCTAssertEqual(WindLayer.hintText(hint, bundle: zh), "空氣由東北方吹來，該方向 PM2.5 較高")

        let reading = WindReading(stationId: "1", name: "臺北", lat: 25, lon: 121.5, speed: 3.2, direction: 45)
        XCTAssertEqual(WindLayer.accessibilityText(reading, chinese: false, bundle: en), "Wind from the north-east at 3.2 metres per second")
        XCTAssertEqual(WindLayer.accessibilityText(reading, chinese: true, bundle: zh), "臺北，東北風，風速每秒 3.2 公尺")
    }

    func testEveryCompassPointHasBothStrings() throws {
        for bundle in [try lproj("en"), try lproj("zh-Hant")] {
            for name in WindLayer.compassNames {
                let key = "WindLayer.from.\(name)"
                XCTAssertNotEqual(NSLocalizedString(key, bundle: bundle, comment: ""), key)
            }
        }
    }
}
