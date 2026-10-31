//
//  AppStoreScreenshotTests.swift
//  TWAQIUITests
//
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest

/// Captures the raw App Store screenshots of the four headline features on
/// iPhone or iPad (the unfolded iPhone Duo still uses DuoScreenshotTests):
///
///   01  the map of every station
///   02  a station: its AQI and every pollutant
///   03  that station's 24-hour PM2.5 chart
///   04  Favourites
///
/// Not part of the normal test run. fastlane's `capture_screenshots` lane runs
/// it once per locale and passes, via `TEST_RUNNER_`-prefixed variables:
///
///   SCREENSHOT_DIR       where the PNGs are written (a path on the Mac)
///   SCREENSHOT_PREFIX    file name prefix: "iPhone" or "iPad"
///   SCREENSHOT_LANGUAGE  "en" or "zh-Hant"
///   SCREENSHOT_MAP_ZOOM  optional; the map's zoom, default 7.2
final class AppStoreScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var outputDir: URL!
    private var prefix = "iPhone"
    private var isChinese = false

    /// Songshan, Banqiao, Xitun and Hualien: north, centre and east coast.
    private static let favouriteStationIds = [105, 106, 112, 104]

    override func setUpWithError() throws {
        continueAfterFailure = false

        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("SCREENSHOT_DIR not set: run through fastlane capture_screenshots")
        }
        outputDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        prefix = env["SCREENSHOT_PREFIX"].flatMap { $0.isEmpty ? nil : $0 } ?? "iPhone"

        let language = env["SCREENSHOT_LANGUAGE"] ?? "en"
        isChinese = language.hasPrefix("zh")
        let zoom = env["SCREENSHOT_MAP_ZOOM"].flatMap { $0.isEmpty ? nil : $0 } ?? "7.2"

        let favourites = Self.favouriteStationIds.map { "<integer>\($0)</integer>" }.joined()

        app = XCUIApplication()
        // NSUserDefaults' argument domain, for this launch only: `pro` hides
        // the ad banners, the camera keys frame the whole island, the
        // favourites are seeded without touching alerts, and the last two
        // pick the language.
        app.launchArguments = [
            "-pro", "YES",
            "-lastestMapLat", "23.7",
            "-lastestMapLon", "121.0",
            "-lastestMapZoom", zoom,
            "-savedFavouriteStations", "<array>\(favourites)</array>",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", isChinese ? "zh_TW" : "en_US",
        ]
        app.launch()
        dismissSystemAlerts()
    }

    func testCaptureAppStoreScreenshots() throws {
        // Stands alone on the east coast, so a tap can't land on a neighbour
        // the way one in the Taipei cluster would.
        let station = isChinese ? "花蓮" : "Hualien"

        // 01: the map.
        let marker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", station))
            .firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 180), "No map marker labelled \(station)")
        settle()
        snapshot("01 map")

        // 02: the station, from its marker — a sheet on iPhone, the panel
        // beside the map in a wide window.
        marker.tap()
        let share = app.buttons[isChinese ? "分享" : "Share"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 60), "Station page did not open")
        let loaded = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: share)
        wait(for: [loaded], timeout: 90)
        // Anything below the reading (forecast, cam frame) arrives after it.
        settle(seconds: 6)
        snapshot("02 station")

        // 03: the pollutants scrolled up to the top, with PM2.5 picked so
        // the chart under them shows its last 24 hours.
        // The section label is drawn in capitals; match it either way.
        let pollutantsLabel = app.staticTexts
            .matching(NSPredicate(format: "label ==[c] %@", isChinese ? "污染物" : "Pollutants"))
            .firstMatch
        XCTAssertTrue(pollutantsLabel.waitForExistence(timeout: 15), "No pollutants section")
        scrollToTop(pollutantsLabel)
        // The grid cell's label carries its reading ("PM2.5, 12, μg/m3"); the
        // map's index chip, also on screen in a wide window, is bare "PM2.5".
        let pm25 = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@ AND label != %@", "PM2.5", "PM2.5"))
            .firstMatch
        XCTAssertTrue(pm25.waitForExistence(timeout: 10), "No PM2.5 cell in the pollutant grid")
        pm25.tap()
        settle()
        snapshot("03 trend")

        // 04: Favourites. The station page is closed first so the tab bar is
        // reachable on iPhone.
        let close = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Close", "關閉")).firstMatch
        if close.exists, close.isHittable {
            close.tap()
        } else if app.buttons["xmark"].exists {
            app.buttons["xmark"].firstMatch.tap()
        }
        settle(seconds: 2)
        let favouritesTab = app.buttons[isChinese ? "最愛" : "Favourites"].firstMatch
        XCTAssertTrue(favouritesTab.waitForExistence(timeout: 10), "No Favourites tab")
        favouritesTab.tap()
        let firstRow = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", isChinese ? "松山" : "Songshan"))
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 90), "Favourites did not load")
        settle()
        snapshot("04 favourites")
    }

    /// Drags `element` up to just under the floating close and share
    /// buttons, slowly so the scroll view doesn't coast past it.
    private func scrollToTop(_ element: XCUIElement) {
        guard element.waitForExistence(timeout: 10) else { return }
        let window = app.windows.firstMatch.frame
        let target = window.minY + window.height * 0.17
        for _ in 0..<3 {
            let y = element.frame.minY
            guard y > target + 20 else { return }
            let distance = min(y - target, window.height * 0.6)
            let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = start.withOffset(CGVector(dx: 0, dy: -distance))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
            settle(seconds: 1)
        }
    }

    /// Location, notification and tracking prompts. Index 1 is the allowing
    /// choice on each, in either language.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 5) else { return }
            let buttons = alert.buttons
            buttons.element(boundBy: min(1, buttons.count - 1)).tap()
        }
    }

    /// Lets data load, frames draw and animations finish before a capture.
    private func settle(seconds: TimeInterval = 4) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
    }

    private func snapshot(_ name: String) {
        // On the Duo XCUIScreen.main can be the dark outer display; the
        // largest screen is the one in use everywhere.
        let screen = XCUIScreen.screens.max {
            $0.screenshot().image.size.width * $0.screenshot().image.size.height
                < $1.screenshot().image.size.width * $1.screenshot().image.size.height
        } ?? XCUIScreen.main
        let png = screen.screenshot().pngRepresentation
        let url = outputDir.appendingPathComponent("\(prefix) \(name).png")
        XCTAssertNoThrow(try png.write(to: url))

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
