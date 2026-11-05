//
//  DuoScreenshotTests.swift
//  TWAQIUITests
//
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest

/// Captures the App Store screenshots for the iPhone Duo's unfolded display,
/// where the app shows two panes side by side.
///
/// Not part of the normal test run. fastlane's `capture_duo_screenshots` lane
/// runs it once per locale and passes, via `TEST_RUNNER_`-prefixed variables:
///
///   SCREENSHOT_DIR       where the PNGs are written (a path on the Mac)
///   SCREENSHOT_LANGUAGE  "en" or "zh-Hant"
final class DuoScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var outputDir: URL!
    private var isChinese = false

    override func setUpWithError() throws {
        continueAfterFailure = false

        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("SCREENSHOT_DIR not set: run through fastlane capture_duo_screenshots")
        }
        outputDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let language = env["SCREENSHOT_LANGUAGE"] ?? "en"
        isChinese = language.hasPrefix("zh")

        app = XCUIApplication()
        // NSUserDefaults' argument domain, for this launch only: `pro` hides
        // the ad banners, the camera keys frame the whole island in the
        // unfolded display, the last two pick the language.
        app.launchArguments = [
            "-pro", "YES",
            "-lastestMapLat", "23.7",
            "-lastestMapLon", "121.0",
            "-lastestMapZoom", "7.2",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", isChinese ? "zh_TW" : "en_US",
        ]
        app.launch()
        dismissSystemAlerts()
    }

    func testCaptureDuoScreenshots() throws {
        // Stands alone on the east coast, so a tap on it can't land on a
        // neighbouring marker the way one in the Taipei cluster would.
        let station = isChinese ? "花蓮" : "Hualien"

        // 01: the map on its own.
        let marker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", station))
            .firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 30), "No map marker labelled \(station)")
        settle()
        snapshot("01")

        // 02: the map with the station panel beside it.
        marker.tap()
        // The map hides its navigation bar; the panel beside it has one.
        XCTAssertTrue(
            app.navigationBars.firstMatch.waitForExistence(timeout: 15),
            "Station panel did not open"
        )
        settle()
        snapshot("02")

        // 03: the station list with that station's details beside it.
        app.buttons[isChinese ? "搜尋" : "Search"].firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15), "No search field")
        search.tap()
        // Typed in English in both languages: the list also matches the
        // English name, and the simulator keyboard can't type Chinese.
        // Return submits the search, which also puts the keyboard away.
        search.typeText("Hualien\n")
        // The row's label is "name, locality" ("name、locality" in Chinese).
        // Matching on the separator skips both the map marker (bare name) and
        // look-alikes such as "Hualien (Meilun)".
        let row = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
                                  station + ",", station + "、"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No list row for \(station)")
        row.tap()
        settle()
        snapshot("03")
    }

    /// Location and notification prompts. Index 1 is "Allow While Using App"
    /// on the first and "Allow" on the second, in either language.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 5) else { return }
            let buttons = alert.buttons
            buttons.element(boundBy: min(1, buttons.count - 1)).tap()
        }
    }

    /// Lets data load, charts draw and animations finish before a capture.
    private func settle() {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 4)
    }

    private func snapshot(_ name: String) {
        // The Duo has two displays and XCUIScreen.main can be the dark outer
        // one, so take the largest screen, which is the unfolded inner one.
        let screen = XCUIScreen.screens.max {
            $0.screenshot().image.size.width * $0.screenshot().image.size.height
                < $1.screenshot().image.size.width * $1.screenshot().image.size.height
        } ?? XCUIScreen.main
        let png = screen.screenshot().pngRepresentation
        let url = outputDir.appendingPathComponent("iPhone Duo \(name).png")
        XCTAssertNoThrow(try png.write(to: url))

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
