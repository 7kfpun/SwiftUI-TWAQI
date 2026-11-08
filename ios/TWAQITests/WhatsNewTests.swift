//
//  WhatsNewTests.swift
//  TWAQITests
//
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class WhatsNewTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WhatsNewTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        WhatsNew.launchClaimed = false
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        WhatsNew.launchClaimed = false
        super.tearDown()
    }

    func testVersionCompareIsNumeric() {
        XCTAssertTrue(WhatsNew.isNewer("3.1.6", than: "3.1.5"))
        XCTAssertTrue(WhatsNew.isNewer("3.10", than: "3.9"))
        XCTAssertTrue(WhatsNew.isNewer("4.0", than: "3.9.9"))
        XCTAssertFalse(WhatsNew.isNewer("3.1.5", than: "3.1.5"))
        XCTAssertFalse(WhatsNew.isNewer("3.1", than: "3.1.0"))
        XCTAssertFalse(WhatsNew.isNewer("3.1.4", than: "3.1.5"))
    }

    func testUpdateFromOlderVersionShowsOnceAfterItIsMarked() {
        let store = WhatsNewStore(defaults: defaults)
        defaults.set("3.1.4", forKey: WhatsNewStore.shownVersionKey)

        XCTAssertTrue(store.showsOnLaunch(version: "3.1.5", onboardingOpensAtLaunch: false))
        XCTAssertTrue(store.markShown("3.1.5"))
        XCTAssertFalse(store.markShown("3.1.5"), "a repeated onAppear counts once")
        XCTAssertFalse(store.showsOnLaunch(version: "3.1.5", onboardingOpensAtLaunch: false))
    }

    func testBuildFromBeforeTheFeatureShowsOnce() {
        let store = WhatsNewStore(defaults: defaults)
        XCTAssertNil(store.shownVersion)
        XCTAssertTrue(store.showsOnLaunch(version: "3.1.5", onboardingOpensAtLaunch: false))
    }

    func testFreshInstallSeesTheWelcomeNotWhatsNew() {
        let store = WhatsNewStore(defaults: defaults)

        XCTAssertFalse(store.showsOnLaunch(version: "3.1.5", onboardingOpensAtLaunch: true))
        XCTAssertEqual(store.shownVersion, "3.1.5")
        XCTAssertFalse(store.showsOnLaunch(version: "3.1.5", onboardingOpensAtLaunch: false))
    }

    func testVersionWithoutAListOpensNothingButIsCounted() {
        let store = WhatsNewStore(defaults: defaults)
        XCTAssertNil(WhatsNew.release(for: "99.0"))
        XCTAssertFalse(store.showsOnLaunch(version: "99.0", onboardingOpensAtLaunch: false))
        XCTAssertEqual(store.shownVersion, "99.0")
    }

    func testRecordNeverMovesBackwards() {
        let store = WhatsNewStore(defaults: defaults)
        store.markShown("3.2.0")
        XCTAssertFalse(store.markShown("3.1.5"))
        XCTAssertEqual(store.shownVersion, "3.2.0")
    }

    func testPermissionPromptsHoldItBack() {
        XCTAssertTrue(WhatsNew.isClearOfPermissionPrompts(locationUndetermined: false, notificationsUndetermined: false))
        XCTAssertFalse(WhatsNew.isClearOfPermissionPrompts(locationUndetermined: true, notificationsUndetermined: false))
        XCTAssertFalse(WhatsNew.isClearOfPermissionPrompts(locationUndetermined: false, notificationsUndetermined: true))
    }

    func testOnlyOneSceneClaimsThePopup() {
        XCTAssertFalse(WhatsNew.claimLaunchPopup(shows: false))
        XCTAssertTrue(WhatsNew.claimLaunchPopup(shows: true))
        XCTAssertFalse(WhatsNew.claimLaunchPopup(shows: true))
    }

    func testCurrentVersionHasAListWithStrings() throws {
        let release = try XCTUnwrap(WhatsNew.release(for: WhatsNew.currentVersion))
        XCTAssertFalse(release.items.isEmpty)
        for item in release.items {
            for key in [item.titleKey, item.bodyKey] {
                XCTAssertNotEqual(key.localized, key, "\(key) is not localized")
            }
        }
    }
}
