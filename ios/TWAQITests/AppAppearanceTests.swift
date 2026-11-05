//
//  AppAppearanceTests.swift
//  TWAQITests
//
//  Created by kf on 5/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import UIKit
import XCTest
@testable import Taiwan_Air

/// FOX-43: light, dark or system look, chosen under Help.
final class AppAppearanceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppAppearanceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testFollowsSystemUntilChosen() {
        XCTAssertEqual(AppAppearance.stored(in: defaults), .system)
        XCTAssertEqual(SettingsStore(defaults: defaults).appearance, .system)
    }

    func testUnknownStoredValueFollowsSystem() {
        defaults.set("sepia", forKey: AppAppearance.defaultsKey)

        XCTAssertEqual(AppAppearance.stored(in: defaults), .system)
    }

    func testChoiceIsStoredAndSystemRemovesIt() {
        let settings = SettingsStore(defaults: defaults)

        settings.appearance = .dark
        XCTAssertEqual(defaults.string(forKey: AppAppearance.defaultsKey), "dark")
        XCTAssertEqual(SettingsStore(defaults: defaults).appearance, .dark)

        settings.appearance = .light
        XCTAssertEqual(settings.appearance, .light)

        settings.appearance = .system
        XCTAssertNil(defaults.object(forKey: AppAppearance.defaultsKey))
        XCTAssertEqual(settings.appearance, .system)
    }

    func testWindowStyleForEachChoice() {
        XCTAssertEqual(AppAppearance.system.userInterfaceStyle, .unspecified)
        XCTAssertEqual(AppAppearance.light.userInterfaceStyle, .light)
        XCTAssertEqual(AppAppearance.dark.userInterfaceStyle, .dark)
    }

    func testApplySetsEveryWindowAndSystemClearsTheOverride() {
        let windows = [UIWindow(), UIWindow()]

        AppAppearance.dark.apply(to: windows)
        XCTAssertEqual(windows.map(\.overrideUserInterfaceStyle), [.dark, .dark])

        AppAppearance.system.apply(to: windows)
        XCTAssertEqual(windows.map(\.overrideUserInterfaceStyle), [.unspecified, .unspecified])
    }
}
