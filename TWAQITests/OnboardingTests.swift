//
//  OnboardingTests.swift
//  TWAQITests
//
//  Created by kf on 2/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import XCTest
@testable import Taiwan_Air

final class OnboardingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Completion persistence

    func testFreshInstallShowsFlowAndDoesNotPromptAtLaunch() {
        let store = OnboardingStore(defaults: defaults)
        store.adoptExistingInstall(hasLaunchedBefore: false)

        XCTAssertFalse(store.isCompleted)
        XCTAssertTrue(store.showsOnLaunch)
        XCTAssertFalse(store.promptsForPushAtLaunch)
    }

    func testCompletionPersistsAcrossStores() {
        OnboardingStore(defaults: defaults).markCompleted()

        // A new store over the same defaults, as on the next launch.
        let nextLaunch = OnboardingStore(defaults: defaults)
        XCTAssertTrue(nextLaunch.isCompleted)
        XCTAssertFalse(nextLaunch.showsOnLaunch)
        // Finishing the flow doesn't bring the launch-time prompt back.
        XCTAssertFalse(nextLaunch.promptsForPushAtLaunch)
    }

    func testFreshInstallThatQuitMidFlowStillGetsTheFlow() {
        let store = OnboardingStore(defaults: defaults)
        store.adoptExistingInstall(hasLaunchedBefore: false)
        // Quit before finishing; the next launch has been counted once.
        store.adoptExistingInstall(hasLaunchedBefore: true)

        XCTAssertFalse(store.isCompleted)
        XCTAssertTrue(store.showsOnLaunch)
        XCTAssertFalse(store.isLegacyInstall)
    }

    func testUpdateFromBuildWithoutFlowIsNotWalkedThrough() {
        let store = OnboardingStore(defaults: defaults)
        store.adoptExistingInstall(hasLaunchedBefore: true)

        XCTAssertTrue(store.isCompleted)
        XCTAssertFalse(store.showsOnLaunch)
        XCTAssertTrue(store.isLegacyInstall)
        // Keeps the launch-time prompt it always had.
        XCTAssertTrue(store.promptsForPushAtLaunch)
    }

    func testRerunFromHelpKeepsCompletion() {
        let store = OnboardingStore(defaults: defaults)
        store.adoptExistingInstall(hasLaunchedBefore: false)
        store.markCompleted()
        // Help runs the flow again and it is finished again.
        store.markCompleted()

        XCTAssertTrue(OnboardingStore(defaults: defaults).isCompleted)
    }

    // MARK: - Steps

    func testStepOrder() {
        XCTAssertEqual(Onboarding.Step.allCases, [
            .welcome, .location, .closestStation, .notifications, .doNotDisturb, .dataSource, .premium,
        ])
        XCTAssertEqual(Onboarding.Step.welcome.next, .location)
        XCTAssertNil(Onboarding.Step.welcome.previous)
        XCTAssertTrue(Onboarding.Step.premium.isLast)
        XCTAssertNil(Onboarding.Step.premium.next)
    }

    // MARK: - Closest station / 中正 fallback

    func testWithoutLocationFallsBackToStationNearestZhongzheng() throws {
        let stations = try [
            station(id: 1, lat: 22.6273, lon: 120.3014),   // Kaohsiung
            station(id: 2, lat: 25.0330, lon: 121.5150),   // next to 中正區
            station(id: 3, lat: 25.0600, lon: 121.5800),   // Songshan, further off
        ]

        let resolved = try XCTUnwrap(OnboardingClosestStation.resolve(location: nil, in: stations))
        XCTAssertEqual(resolved.pollutant.stationId, 2)
        XCTAssertTrue(resolved.isFallback)
    }

    func testFallbackUsesTheWatchDefault() throws {
        // One shared definition: the same point the Watch app falls back to.
        let stations = try [
            station(id: 7, lat: WatchAPI.defaultLocation.coordinate.latitude, lon: WatchAPI.defaultLocation.coordinate.longitude),
            station(id: 8, lat: 25.10, lon: 121.60),
        ]
        XCTAssertEqual(OnboardingClosestStation.resolve(location: nil, in: stations)?.pollutant.stationId, 7)
    }

    func testWithLocationPicksNearestStation() throws {
        let stations = try [
            station(id: 1, lat: 22.6273, lon: 120.3014),
            station(id: 2, lat: 25.0330, lon: 121.5150),
        ]
        let kaohsiung = CLLocation(latitude: 22.63, longitude: 120.30)

        let resolved = try XCTUnwrap(OnboardingClosestStation.resolve(location: kaohsiung, in: stations))
        XCTAssertEqual(resolved.pollutant.stationId, 1)
        XCTAssertFalse(resolved.isFallback)
    }

    func testNoStationsResolvesToNothing() {
        XCTAssertNil(OnboardingClosestStation.resolve(location: nil, in: []))
    }

    private func station(id: Int, lat: Double, lon: Double) throws -> Pollutant {
        let json = """
        {"station_id": \(id), "lat": \(lat), "lon": \(lon), "aqi": 42, "pm25": 10, "pm10": 20,
         "no2": 1, "so2": 1, "co": 0.1, "o3": 30, "wind_direction": 0, "wind_speed": 0,
         "publish_time": "2026-11-02 10:00:00", "name": {"en": "Station \(id)", "zh": "測站\(id)"}}
        """
        return try JSONDecoder().decode(Pollutant.self, from: Data(json.utf8))
    }
}
