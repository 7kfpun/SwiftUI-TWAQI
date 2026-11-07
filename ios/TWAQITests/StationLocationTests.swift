//
//  StationLocationTests.swift
//  TWAQITests
//
//  Created by kf on 6/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import XCTest

@testable import Taiwan_Air

/// The station page's small map (FOX-124): shown only for a real position,
/// and tapping it opens that position in Apple Maps.
final class StationLocationTests: XCTestCase {
    // MARK: - Position

    func testStationPositionIsKept() throws {
        let coordinate = try XCTUnwrap(StationMiniMap.coordinate(lat: 25.129167, lon: 121.760056))
        XCTAssertEqual(coordinate.latitude, 25.129167, accuracy: 1e-9)
        XCTAssertEqual(coordinate.longitude, 121.760056, accuracy: 1e-9)
    }

    /// The API sends 0, 0 for a station it has no position for: no map, as on Android.
    func testZeroZeroHasNoMap() {
        XCTAssertNil(StationMiniMap.coordinate(lat: 0, lon: 0))
    }

    /// Only both zero means "missing"; one zero is still a place.
    func testOneZeroIsStillAPosition() {
        XCTAssertNotNil(StationMiniMap.coordinate(lat: 0, lon: 121.5))
        XCTAssertNotNil(StationMiniMap.coordinate(lat: 25, lon: 0))
    }

    func testOutOfRangeOrNonFiniteHasNoMap() {
        XCTAssertNil(StationMiniMap.coordinate(lat: 91, lon: 121))
        XCTAssertNil(StationMiniMap.coordinate(lat: 25, lon: 181))
        XCTAssertNil(StationMiniMap.coordinate(lat: .nan, lon: 121))
        XCTAssertNil(StationMiniMap.coordinate(lat: 25, lon: .infinity))
    }

    func testViewHidesMapWithoutPosition() {
        let view = StationLocationView(
            address: "臺北市", coordinateText: "0.000000, 0.000000",
            lat: 0, lon: 0, stationName: "Test", aqi: 40
        )
        XCTAssertNil(view.coordinate)
        XCTAssertTrue(view.hasContent)
    }

    func testViewHasMapWithPosition() {
        let view = StationLocationView(
            address: nil, coordinateText: "25.129167, 121.760056",
            lat: 25.129167, lon: 121.760056, stationName: "Keelung", aqi: 40
        )
        XCTAssertNotNil(view.coordinate)
    }

    // MARK: - Apple Maps link

    func testAppleMapsURLPinsTheStation() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 25.129167, longitude: 121.760056)
        let url = try XCTUnwrap(StationMiniMap.appleMapsURL(coordinate: coordinate, name: "Keelung"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "maps.apple.com")
        XCTAssertEqual(components.queryItems?.first { $0.name == "ll" }?.value, "25.129167,121.760056")
        XCTAssertEqual(components.queryItems?.first { $0.name == "q" }?.value, "Keelung")
    }

    /// Chinese names and spaces are percent-encoded and come back intact.
    func testAppleMapsURLEncodesTheName() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 25.0, longitude: 121.5)
        let url = try XCTUnwrap(StationMiniMap.appleMapsURL(coordinate: coordinate, name: "基隆 & 板橋"))
        XCTAssertFalse(url.absoluteString.contains(" "))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "q" }?.value, "基隆 & 板橋")
    }

    func testAppleMapsURLLeavesOutABlankName() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 25.0, longitude: 121.5)
        let url = try XCTUnwrap(StationMiniMap.appleMapsURL(coordinate: coordinate, name: "  "))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertNil(components.queryItems?.first { $0.name == "q" })
        XCTAssertEqual(components.queryItems?.first { $0.name == "ll" }?.value, "25.000000,121.500000")
    }

    // MARK: - Zoom

    func testRegionIsCentredOnTheStationAtNeighbourhoodZoom() {
        let coordinate = CLLocationCoordinate2D(latitude: 25.129167, longitude: 121.760056)
        let region = StationMiniMap.region(around: coordinate)
        XCTAssertEqual(region.center.latitude, coordinate.latitude, accuracy: 1e-9)
        XCTAssertEqual(region.center.longitude, coordinate.longitude, accuracy: 1e-9)
        // 1.5 km is about 0.0135° of latitude.
        XCTAssertEqual(region.span.latitudeDelta, 0.0135, accuracy: 0.001)
    }
}
