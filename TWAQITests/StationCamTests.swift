//
//  StationCamTests.swift
//  TWAQITests
//
//  Created by kf on 30/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class StationCamTests: XCTestCase {

    /// A slice of the live manifest: ids and coordinates as MOENV publishes them.
    private let manifest = """
    {
      "updatedAt": "2026-10-30T15:00:59.613Z",
      "stations": {
        "001": { "name": "基隆", "lat": 25.129167, "lon": 121.760056, "time": "2026-10-30T22:30:00+08:00", "key": "stations/001.jpg" },
        "057": { "name": "前鎮", "lat": 22.6044507, "lon": 120.30833356, "time": "2026-10-30T22:30:00+08:00", "key": "stations/057.jpg" },
        "088": { "name": "臺灣大道", "lat": 24.1589, "lon": 120.6567111, "time": "2026-10-30T22:30:00+08:00", "key": "stations/088.jpg" },
        "204": { "name": "屏東（琉球）", "lat": 22.35222, "lon": 120.37722, "time": "2026-10-30T22:30:00+08:00", "key": "stations/204.jpg" }
      }
    }
    """

    private var cams: [StationCam] {
        try! JSONDecoder().decode(StationCamManifest.self, from: Data(manifest.utf8)).cams
    }

    func testDecodesManifestKeyedBySiteId() {
        XCTAssertEqual(cams.map(\.siteId), ["001", "057", "088", "204"])
        XCTAssertEqual(cams.first?.name, "基隆")
    }

    /// 基隆 is station 91 in the AQI API and 001 at MOENV. The URL must carry 001.
    func testImageURLUsesMoenvSiteId() {
        let cam = StationCamMatcher.match(name: "基隆", lat: 25.129167, lon: 121.760056, in: cams)
        XCTAssertEqual(cam?.siteId, "001")
        XCTAssertEqual(cam?.imageURL.path, "/stations/001.jpg")
        XCTAssertEqual(cam?.imageURL.host, "twaqi.app.wahthefox.com")
    }

    func testImageURLIsVersionedByCaptureTime() {
        let query = cams[0].imageURL.query ?? ""
        XCTAssertTrue(query.hasPrefix("t="))
        XCTAssertTrue(query.contains("2026-10-30T22"))
    }

    func testMatchesByNameEvenWhenCoordinatesDisagree() {
        let cam = StationCamMatcher.match(name: "基隆", lat: 0, lon: 0, in: cams)
        XCTAssertEqual(cam?.siteId, "001")
    }

    func testNameMatchIgnoresParenthesisWidthAndTaiVariant() {
        XCTAssertEqual(StationCamMatcher.match(name: "屏東(琉球)", lat: 0, lon: 0, in: cams)?.siteId, "204")
        XCTAssertEqual(StationCamMatcher.match(name: "台灣大道", lat: 0, lon: 0, in: cams)?.siteId, "088")
    }

    func testFallsBackToANearbyCamWhenTheNameDiffers() {
        let cam = StationCamMatcher.match(name: "Keelung", lat: 25.1292, lon: 121.7601, in: cams)
        XCTAssertEqual(cam?.siteId, "001")
    }

    /// 復興 has no cam; 前鎮's is 610 m away and shows a different street.
    func testDoesNotBorrowANeighboursCam() {
        let cam = StationCamMatcher.match(name: "復興", lat: 22.608711, lon: 120.312017, in: cams)
        XCTAssertNil(cam)
    }

    func testNoCoordinatesAndNoNameMatchIsMissing() {
        XCTAssertNil(StationCamMatcher.match(name: "", lat: 0, lon: 0, in: cams))
    }
}
