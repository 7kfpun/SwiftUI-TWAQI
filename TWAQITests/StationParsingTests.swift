//
//  StationParsingTests.swift
//  TWAQITests
//
//  Created by kf on 8/8/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftyJSON
import XCTest
@testable import Taiwan_Air

final class StationParsingTests: XCTestCase {

    /// A fully populated station, as /v1/stations returns for the EPA sites.
    private let complete = JSON([
        "id": 91,
        "country_id": 3,
        "code": "基隆",
        "name": ["zh": "基隆", "en": "Keelung"],
        "address": ["zh": "基隆市東信路324號"],
        "area": ["zh": "北部空品區", "en": "North"],
        "station_type": "GENERAL",
        "additional_info": [
            "county": ["zh": "基隆市", "en": "Keelung City"],
            "township": ["zh": "信義區"],
        ],
        "lat": 25.129167,
        "lon": 121.760056,
        "image_url": "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=1&type=l",
    ] as [String: Any])

    /// A micro-sensor station. The API returns these with every nested object
    /// empty and no English name — the shape that used to crash the list.
    private let sparse = JSON([
        "id": 17281,
        "country_id": 3,
        "code": "臺灣大道",
        "name": ["zh": "臺灣大道"],
        "address": [:],
        "area": [:],
        "station_type": "",
        "additional_info": [:],
        "lat": 24.1589,
        "lon": 120.656711,
        "image_url": "",
    ] as [String: Any])

    // MARK: - Complete payload

    func testParsesIdentity() {
        let station = Station.make(from: complete)

        XCTAssertEqual(station.id, 91)
        XCTAssertEqual(station.countryId, 3)
        XCTAssertEqual(station.code, "基隆")
        XCTAssertEqual(station.name, "Keelung")
        XCTAssertEqual(station.nameLocal, "基隆")
    }

    func testParsesCoordinates() {
        let station = Station.make(from: complete)

        XCTAssertEqual(station.lat, 25.129167, accuracy: 0.000001)
        XCTAssertEqual(station.lon, 121.760056, accuracy: 0.000001)
    }

    func testParsesLocationDetail() {
        let station = Station.make(from: complete)

        XCTAssertEqual(station.address, "基隆市東信路324號")
        XCTAssertEqual(station.area, "North")
        XCTAssertEqual(station.areaLocal, "北部空品區")
        XCTAssertEqual(station.county, "Keelung City")
        XCTAssertEqual(station.countyLocal, "基隆市")
        XCTAssertEqual(station.township, "信義區")
    }

    /// Regression: this used to read the "zoom" key and so was always nil.
    func testParsesImageUrl() {
        XCTAssertEqual(
            Station.make(from: complete).imageUrl,
            "https://taqm.epa.gov.tw/taqm/webcam.ashx?site=1&type=l"
        )
    }

    func testParsesStationType() {
        XCTAssertEqual(Station.make(from: complete).stationType, .general)
    }

    // MARK: - Sparse payload

    func testSparseStationDegradesToNilRatherThanCrashing() {
        let station = Station.make(from: sparse)

        XCTAssertNil(station.address)
        XCTAssertNil(station.area)
        XCTAssertNil(station.areaLocal)
        XCTAssertNil(station.county)
        XCTAssertNil(station.countyLocal)
        XCTAssertNil(station.township)
    }

    /// An empty image_url must become nil, not an empty string that renders as
    /// a broken image.
    func testEmptyImageUrlBecomesNil() {
        XCTAssertNil(Station.make(from: sparse).imageUrl)
    }

    /// With no English name, the Chinese one stands in for both — never blank.
    func testMissingEnglishNameFallsBackToLocal() {
        let station = Station.make(from: sparse)

        XCTAssertEqual(station.name, "臺灣大道")
        XCTAssertEqual(station.nameLocal, "臺灣大道")
    }

    func testUnknownStationTypeForEmptyString() {
        XCTAssertEqual(Station.make(from: sparse).stationType, .unknown)
    }

    // MARK: - Key casing

    /// /v1/stations uses snake_case; the station object on
    /// /v1/historical-pollutants has used camelCase. Both must parse.
    func testAcceptsCamelCaseCountryKeys() {
        let camel = JSON([
            "id": 63,
            "countryId": 3,
            "countryCode": "twn",
            "code": "臺西",
            "name": ["zh": "臺西", "en": "Taixi"],
            "lat": 23.717533,
            "lon": 120.202842,
        ] as [String: Any])

        let station = Station.make(from: camel)

        XCTAssertEqual(station.countryId, 3)
        XCTAssertEqual(station.countryCode, "twn")
    }

    func testMissingCountryKeysDefaultRatherThanCrash() {
        let station = Station.make(from: JSON(["id": 1] as [String: Any]))

        XCTAssertEqual(station.countryId, 0)
        XCTAssertEqual(station.countryCode, "")
        XCTAssertEqual(station.lat, 0)
        XCTAssertEqual(station.lon, 0)
    }

    // MARK: - Display helpers

    func testDisplayNameFallsBackToCodeThenId() {
        let noName = Station(
            id: 42,
            countryId: 3,
            countryCode: "twn",
            code: "",
            lat: 0,
            lon: 0,
            name: "",
            nameLocal: ""
        )

        XCTAssertEqual(noName.displayName, "#42")
    }

    func testDisplayAreaIsNilWhenBlank() {
        var station = Station.make(from: complete)
        station.area = ""
        station.areaLocal = ""

        XCTAssertNil(station.displayArea)
    }
}
