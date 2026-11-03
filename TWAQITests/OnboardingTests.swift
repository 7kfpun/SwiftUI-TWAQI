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

    // MARK: - Shown once (FOX-49)

    func testFreshInstallShowsFlowAndDoesNotPromptAtLaunch() {
        let store = OnboardingStore(defaults: defaults)
        store.prepareForLaunch(hasLaunchedBefore: false)

        XCTAssertTrue(store.showsOnLaunch)
        XCTAssertFalse(store.isLegacyInstall)
        XCTAssertFalse(store.promptsForPushAtLaunch)
    }

    func testShownPersistsUnderTheVersionedKey() {
        let store = OnboardingStore(defaults: defaults)
        store.prepareForLaunch(hasLaunchedBefore: false)
        store.markShown()

        XCTAssertEqual(defaults.integer(forKey: "onboardingShownVersion"), OnboardingStore.currentVersion)
        // A new store over the same defaults, as on the next launch or after an update.
        let nextLaunch = OnboardingStore(defaults: defaults)
        nextLaunch.prepareForLaunch(hasLaunchedBefore: true)
        XCTAssertFalse(nextLaunch.showsOnLaunch)
        // Seeing the flow doesn't bring the launch-time prompt back.
        XCTAssertFalse(nextLaunch.promptsForPushAtLaunch)
    }

    func testQuitMidFlowIsNotShownAgain() {
        // Marked when it opens; the app is killed before Done or Skip.
        let store = OnboardingStore(defaults: defaults)
        store.prepareForLaunch(hasLaunchedBefore: false)
        store.markShown()

        let nextLaunch = OnboardingStore(defaults: defaults)
        nextLaunch.prepareForLaunch(hasLaunchedBefore: true)
        XCTAssertFalse(nextLaunch.showsOnLaunch)
    }

    func testUpdateFromBuildWithoutFlowSeesItOnce() {
        let store = OnboardingStore(defaults: defaults)
        store.prepareForLaunch(hasLaunchedBefore: true)

        XCTAssertTrue(store.isLegacyInstall)
        XCTAssertTrue(store.showsOnLaunch)
        // Not on the launch the flow opens: it asks on its own step.
        XCTAssertFalse(store.promptsForPushAtLaunch)

        store.markShown()
        let nextLaunch = OnboardingStore(defaults: defaults)
        nextLaunch.prepareForLaunch(hasLaunchedBefore: true)
        XCTAssertFalse(nextLaunch.showsOnLaunch)
        // Keeps the launch-time prompt it always had afterwards.
        XCTAssertTrue(nextLaunch.promptsForPushAtLaunch)
    }

    func testOlderInstallMarkedDoneByFox34StillSeesItOnce() {
        // What a FOX-34 build wrote for an install older than the flow.
        defaults.set(true, forKey: "onboardingInstallChecked")
        defaults.set(true, forKey: "onboardingCompleted")
        defaults.set(true, forKey: "onboardingLegacyInstall")

        let store = OnboardingStore(defaults: defaults)
        store.prepareForLaunch(hasLaunchedBefore: true)
        XCTAssertTrue(store.showsOnLaunch)
    }

    func testFox34InstallThatQuitMidFlowSeesItOnce() {
        // A FOX-34 fresh install killed before Done or Skip: nothing marked.
        defaults.set(true, forKey: "onboardingInstallChecked")

        let store = OnboardingStore(defaults: defaults)
        store.prepareForLaunch(hasLaunchedBefore: true)
        XCTAssertTrue(store.showsOnLaunch)
        XCTAssertFalse(store.isLegacyInstall)
    }

    func testFlowFinishedOnFox34BuildCountsAsShown() {
        // A FOX-34 fresh install that finished or skipped the flow.
        defaults.set(true, forKey: "onboardingInstallChecked")
        defaults.set(true, forKey: "onboardingCompleted")

        let store = OnboardingStore(defaults: defaults)
        store.prepareForLaunch(hasLaunchedBefore: true)
        XCTAssertFalse(store.showsOnLaunch)
        XCTAssertEqual(store.shownVersion, 1)
        XCTAssertFalse(store.promptsForPushAtLaunch)
    }

    func testRaisingTheVersionShowsItOnceMore() {
        OnboardingStore(defaults: defaults, currentVersion: 1).markShown()

        let reworked = OnboardingStore(defaults: defaults, currentVersion: 2)
        reworked.prepareForLaunch(hasLaunchedBefore: true)
        XCTAssertTrue(reworked.showsOnLaunch)
        reworked.markShown()
        XCTAssertFalse(OnboardingStore(defaults: defaults, currentVersion: 2).showsOnLaunch)
    }

    func testMarkShownRecordsOnlyTheFirstTime() {
        let store = OnboardingStore(defaults: defaults)
        XCTAssertTrue(store.markShown())
        // A second `onAppear` for the same cover.
        XCTAssertFalse(store.markShown())
    }

    func testMarkShownNeverLowersTheVersion() {
        OnboardingStore(defaults: defaults, currentVersion: 2).markShown()
        OnboardingStore(defaults: defaults, currentVersion: 1).markShown()

        XCTAssertEqual(OnboardingStore(defaults: defaults).shownVersion, 2)
    }

    // MARK: - Launch hold

    func testReleasingTheLaunchHoldClearsItAndPostsOnce() {
        let center = NotificationCenter()
        let posts = PostCount()
        let token = center.addObserver(forName: Onboarding.didFinish, object: nil, queue: nil) { _ in posts.value += 1 }
        defer { center.removeObserver(token) }
        let saved = Onboarding.isOpenAtLaunch
        defer { Onboarding.isOpenAtLaunch = saved }

        Onboarding.isOpenAtLaunch = true
        Onboarding.releaseLaunchHold(notificationCenter: center)
        XCTAssertFalse(Onboarding.isOpenAtLaunch)
        XCTAssertEqual(posts.value, 1)

        // Finished, then its scene goes too: nothing more to release.
        Onboarding.releaseLaunchHold(notificationCenter: center)
        XCTAssertEqual(posts.value, 1)
    }

    func testReleasingWithoutALaunchHoldPostsNothing() {
        let center = NotificationCenter()
        let posts = PostCount()
        let token = center.addObserver(forName: Onboarding.didFinish, object: nil, queue: nil) { _ in posts.value += 1 }
        defer { center.removeObserver(token) }
        let saved = Onboarding.isOpenAtLaunch
        defer { Onboarding.isOpenAtLaunch = saved }

        // A Help run, or a launch the flow didn't open on.
        Onboarding.isOpenAtLaunch = false
        Onboarding.releaseLaunchHold(notificationCenter: center)
        XCTAssertFalse(Onboarding.isOpenAtLaunch)
        XCTAssertEqual(posts.value, 0)
    }

    func testFinishingAHelpRunLeavesTheLaunchHold() {
        let center = NotificationCenter()
        let posts = PostCount()
        let token = center.addObserver(forName: Onboarding.didFinish, object: nil, queue: nil) { _ in posts.value += 1 }
        defer { center.removeObserver(token) }
        let saved = Onboarding.isOpenAtLaunch
        defer { Onboarding.isOpenAtLaunch = saved }

        // The launch run is still up in one iPad window; Help's run in
        // another is finished.
        Onboarding.isOpenAtLaunch = true
        Onboarding.flowEnded(isLaunchFlow: false, notificationCenter: center)
        XCTAssertTrue(Onboarding.isOpenAtLaunch)
        XCTAssertEqual(posts.value, 0)
    }

    func testFinishingTheLaunchRunReleasesTheHold() {
        let center = NotificationCenter()
        let posts = PostCount()
        let token = center.addObserver(forName: Onboarding.didFinish, object: nil, queue: nil) { _ in posts.value += 1 }
        defer { center.removeObserver(token) }
        let saved = Onboarding.isOpenAtLaunch
        defer { Onboarding.isOpenAtLaunch = saved }

        Onboarding.isOpenAtLaunch = true
        Onboarding.flowEnded(isLaunchFlow: true, notificationCenter: center)
        XCTAssertFalse(Onboarding.isOpenAtLaunch)
        XCTAssertEqual(posts.value, 1)
    }

    func testOnlyTheFirstSceneOpensTheLaunchFlow() {
        let saved = Onboarding.launchFlowClaimed
        defer { Onboarding.launchFlowClaimed = saved }
        Onboarding.launchFlowClaimed = false

        // Two iPad windows restored together on the launch that shows it.
        XCTAssertTrue(Onboarding.claimLaunchFlow(showsOnLaunch: true))
        XCTAssertFalse(Onboarding.claimLaunchFlow(showsOnLaunch: true))
    }

    func testNoSceneClaimsTheFlowWhenItDoesNotShow() {
        let saved = Onboarding.launchFlowClaimed
        defer { Onboarding.launchFlowClaimed = saved }
        Onboarding.launchFlowClaimed = false

        XCTAssertFalse(Onboarding.claimLaunchFlow(showsOnLaunch: false))
        XCTAssertFalse(Onboarding.launchFlowClaimed)
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

private final class PostCount: @unchecked Sendable {
    var value = 0
}
