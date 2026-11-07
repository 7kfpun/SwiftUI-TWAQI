//
//  MapMarkerTests.swift
//  TWAQITests
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

/// FOX-69: the map keeps its markers and only restyles those whose look
/// changed, so stepping through the timeline doesn't rebuild every marker.
final class MapMarkerTests: XCTestCase {
    // MARK: - MarkerAppearance

    func testSameReadingSameAppearance() throws {
        let first = try appearance(station(aqi: 42))
        let second = try appearance(station(aqi: 42, publishTime: "2026-11-04T09:00:00"))
        XCTAssertEqual(first, second, "Only what is drawn counts, not the publish time")
    }

    func testDifferentReadingDifferentAppearance() throws {
        XCTAssertNotEqual(try appearance(station(aqi: 42)), try appearance(station(aqi: 43)))
    }

    func testPillShowsReadingOnItsBand() throws {
        let look = try appearance(station(aqi: 42))
        XCTAssertEqual(look.shape, .pill(text: "42", foregroundColor: 0xFFFFFF))
        XCTAssertEqual(look.color, 0x009866)
        XCTAssertEqual(look.opacity, 1)
    }

    /// No reading that hour: grey "-", faded.
    func testMissingReadingIsGreyDashFaded() throws {
        let look = try appearance(station(aqi: 0), hasData: false)
        XCTAssertEqual(look.shape, .pill(text: "-", foregroundColor: 0xFFFFFF))
        XCTAssertEqual(look.color, 0x676767)
        XCTAssertEqual(look.opacity, 0.55)
    }

    /// Outside the supported country stays at its own, lower opacity.
    func testMutedStationKeepsItsOpacityWhenMissing() throws {
        XCTAssertEqual(try appearance(station(aqi: 42), isInteractive: false).opacity, 0.4)
        XCTAssertEqual(try appearance(station(aqi: 42), isInteractive: false, hasData: false).opacity, 0.4)
    }

    func testWindModeDrawsArrowOrCalm() throws {
        let windy = try appearance(station(aqi: 42, windDirection: 270, windSpeed: 2), isWindMode: true)
        XCTAssertEqual(windy.shape, .arrow(strength: 0.25, bearing: 270))
        XCTAssertEqual(windy.color, 0x009866)

        let still = try appearance(station(aqi: 42, windDirection: 0, windSpeed: 0), isWindMode: true)
        XCTAssertEqual(still.shape, .calm)
    }

    func testIndexChangeChangesAppearance() throws {
        let pollutant = try station(aqi: 42)
        XCTAssertNotEqual(
            MarkerAppearance(pollutant: pollutant, airIndexType: .aqi, isWindMode: false, isInteractive: true),
            MarkerAppearance(pollutant: pollutant, airIndexType: .pm25, isWindMode: false, isInteractive: true)
        )
    }

    // MARK: - MarkerUpdatePlan

    func testPlanAddsNewStationsAndRemovesGoneOnes() {
        let plan = MarkerUpdatePlan(current: [1, 2, 3], wanted: [1, 2, 4])
        XCTAssertEqual(plan.add, [4])
        XCTAssertEqual(plan.remove, [3])
    }

    /// Scrubbing keeps every station on the map: nothing added or removed.
    func testPlanForSameStationsIsEmpty() {
        let plan = MarkerUpdatePlan(current: [1, 2], wanted: [1, 2])
        XCTAssertTrue(plan.add.isEmpty)
        XCTAssertTrue(plan.remove.isEmpty)
    }

    func testPlanFromEmptyMapAddsEverything() {
        let plan = MarkerUpdatePlan<Int>(current: [], wanted: [1, 2])
        XCTAssertEqual(plan.add, [1, 2])
        XCTAssertTrue(plan.remove.isEmpty)
    }

    // MARK: - MarkerIcons

    func testPillIconIsDrawnOnceAndReused() {
        let first = MarkerIcons.pill(text: "42", color: 0x009866, foregroundColor: 0xFFFFFF)
        let second = MarkerIcons.pill(text: "42", color: 0x009866, foregroundColor: 0xFFFFFF)
        XCTAssertTrue(first === second)
        XCTAssertEqual(first.size, CGSize(width: 40, height: 30))

        let other = MarkerIcons.pill(text: "43", color: 0x009866, foregroundColor: 0xFFFFFF)
        XCTAssertFalse(first === other)
    }

    func testWindIconsAreReused() {
        XCTAssertTrue(MarkerIcons.arrow(strength: 0.25, color: 0x009866) === MarkerIcons.arrow(strength: 0.25, color: 0x009866))
        XCTAssertTrue(MarkerIcons.calm(color: 0x009866) === MarkerIcons.calm(color: 0x009866))
    }

    // MARK: - Marker

    func testMarkerKeepsIconWhenAppearanceUnchanged() throws {
        let pollutant = try station(aqi: 42)
        let look = MarkerAppearance(pollutant: pollutant, airIndexType: .aqi, isWindMode: false, isInteractive: true)
        let marker = StationMapMarker(pollutant: pollutant, appearance: look, isInteractive: true)
        let icon = marker.icon

        marker.update(pollutant: try station(aqi: 42, publishTime: "2026-11-04T08:00:00"), appearance: look, isInteractive: true)
        XCTAssertTrue(marker.icon === icon)
        XCTAssertEqual(marker.pollutant.publishTime, "2026-11-04T08:00:00")

        let worse = try station(aqi: 60)
        marker.update(
            pollutant: worse,
            appearance: MarkerAppearance(pollutant: worse, airIndexType: .aqi, isWindMode: false, isInteractive: true),
            isInteractive: true
        )
        XCTAssertFalse(marker.icon === icon, "A changed reading is restyled")

        let windy = try station(aqi: 42, windDirection: 90, windSpeed: 3)
        marker.update(
            pollutant: windy,
            appearance: MarkerAppearance(pollutant: windy, airIndexType: .aqi, isWindMode: true, isInteractive: false),
            isInteractive: false
        )
        XCTAssertFalse(marker.isInteractive)
        XCTAssertEqual(marker.opacity, 0.4)
        XCTAssertEqual(marker.rotation, 90)
        XCTAssertTrue(marker.isFlat)
        XCTAssertEqual(marker.groundAnchor, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(marker.title, windy.displayName)
    }

    // MARK: - Helpers

    private func appearance(
        _ pollutant: Pollutant,
        isWindMode: Bool = false,
        isInteractive: Bool = true,
        hasData: Bool = true
    ) -> MarkerAppearance {
        MarkerAppearance(
            pollutant: pollutant,
            airIndexType: .aqi,
            isWindMode: isWindMode,
            isInteractive: isInteractive,
            hasData: hasData
        )
    }

    private func station(
        aqi: Double,
        windDirection: Double = 0,
        windSpeed: Double = 0,
        publishTime: String = "2026-11-04T10:00:00"
    ) throws -> Pollutant {
        let json = """
        {"station_id": 1, "lat": 25.0, "lon": 121.5, "aqi": \(aqi), "pm25": 10, "pm10": 20,
         "no2": 1, "so2": 1, "co": 0.1, "o3": 30, "wind_direction": \(windDirection), "wind_speed": \(windSpeed),
         "publish_time": "\(publishTime)", "name": {"en": "Station 1", "zh": "測站1"}}
        """
        return try JSONDecoder().decode(Pollutant.self, from: Data(json.utf8))
    }

    // MARK: - Refresh timer (FOX-135)

    /// Closing an iPad window drops its map controller; the repeating refresh
    /// timer must not keep it alive.
    func testRefreshTimerDoesNotRetainController() {
        weak var weakController: GoogleMapViewController?
        var timer: Timer?
        autoreleasepool {
            let controller = GoogleMapViewController()
            controller.startRefreshTimer()
            timer = controller.refreshTimer
            XCTAssertEqual(timer?.isValid, true)
            weakController = controller
        }
        XCTAssertNil(weakController, "The map controller leaked")
        XCTAssertEqual(timer?.isValid, false, "deinit invalidates the timer")
    }

    func testStopRefreshTimerInvalidates() {
        let controller = GoogleMapViewController()
        controller.startRefreshTimer()
        let timer = controller.refreshTimer
        controller.stopRefreshTimer()
        XCTAssertEqual(timer?.isValid, false)
        XCTAssertNil(controller.refreshTimer)
    }
}
