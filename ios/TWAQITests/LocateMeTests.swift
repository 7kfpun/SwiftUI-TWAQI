//
//  LocateMeTests.swift
//  TWAQITests
//
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import XCTest
@testable import Taiwan_Air

/// FOX-185: the locate-me button's states, permission handling and zoom.
final class LocateMeTests: XCTestCase {
    func testTapsStepOffCentredFollowingThenRecentre() {
        XCTAssertEqual(LocateMeMode.off.afterTap, .centred)
        XCTAssertEqual(LocateMeMode.centred.afterTap, .following)
        XCTAssertEqual(LocateMeMode.following.afterTap, .centred)
    }

    func testDragStopsFollowing() {
        XCTAssertEqual(LocateMeMode.following.afterGesture, .off)
        XCTAssertEqual(LocateMeMode.centred.afterGesture, .off)
    }

    func testAccessFromAuthorization() {
        XCTAssertEqual(LocateMeAccess(status: .notDetermined), .ask)
        XCTAssertEqual(LocateMeAccess(status: .authorizedWhenInUse), .allowed)
        XCTAssertEqual(LocateMeAccess(status: .authorizedAlways), .allowed)
        XCTAssertEqual(LocateMeAccess(status: .denied), .explain)
        XCTAssertEqual(LocateMeAccess(status: .restricted), .explain)
        XCTAssertEqual(LocateMeAccess(status: .notDetermined, servicesEnabled: false), .explain,
                       "Location off system-wide explains instead of asking")
    }

    func testNearestStation() throws {
        let stations = [
            (id: 1, latitude: 25.03, longitude: 121.56),
            (id: 2, latitude: 22.63, longitude: 120.30)
        ]
        let taipei = CLLocationCoordinate2D(latitude: 25.04, longitude: 121.55)
        let nearest = try XCTUnwrap(LocateMe.nearest(to: taipei, in: stations))
        XCTAssertEqual(nearest.id, 1)
        XCTAssertLessThan(nearest.distance, 2_000)
        XCTAssertNil(LocateMe.nearest(to: taipei, in: []))
    }

    func testZoomIsClampedAndTighterForNearerStations() {
        let near = LocateMe.zoom(latitude: 25, nearestStationDistance: 800)
        let far = LocateMe.zoom(latitude: 25, nearestStationDistance: 20_000)
        XCTAssertGreaterThan(near, far)
        XCTAssertEqual(LocateMe.zoom(latitude: 25, nearestStationDistance: 1), LocateMe.maxZoom)
        XCTAssertEqual(LocateMe.zoom(latitude: 25, nearestStationDistance: 500_000), LocateMe.minZoom)
        XCTAssertEqual(LocateMe.zoom(latitude: 25, nearestStationDistance: nil), 13)
    }

    func testHaloRadius() {
        XCTAssertEqual(LocateMe.haloRadius(horizontalAccuracy: 65), 65)
        XCTAssertEqual(LocateMe.haloRadius(horizontalAccuracy: 3), 20, "A floor keeps the halo visible")
        XCTAssertEqual(LocateMe.haloRadius(horizontalAccuracy: 90_000), 1_500, "A poor fix is capped")
        XCTAssertNil(LocateMe.haloRadius(horizontalAccuracy: -1))
    }
}
