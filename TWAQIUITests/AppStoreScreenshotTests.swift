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
///
/// It writes nothing to OneSignal or Directus: the welcome flow is marked
/// done, so a fresh install is never asked for notifications, a stray
/// notification prompt is turned down, and no alert switch or heart is
/// tapped. The station shot is checked to show the alerts card (FOX-25)
/// switched off and unlocked before it is taken.
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
        // the ad banners, `onboardingCompleted` skips the welcome flow (and
        // with it the notification prompt), the camera keys frame the whole
        // island, the favourites are seeded without touching alerts, and the
        // last two pick the language.
        app.launchArguments = [
            "-pro", "YES",
            "-onboardingCompleted", "YES",
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
        assertAlertsCardOffAndUnlocked()
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
        // A tap while the page is still settling from the drags can be taken
        // as "stop scrolling" and select nothing, so check and tap again.
        for _ in 0..<3 where !pm25.isSelected {
            settle(seconds: 2)
            pm25.tap()
        }
        XCTAssertTrue(pm25.isSelected, "PM2.5 isn't picked, so the chart shows AQI")
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
    ///
    /// Since FOX-25 the alerts card and health advice sit above the
    /// pollutants, so they start well below the fold. Each drag starts in
    /// the scroll view's right gutter, clear of the switches and the cam
    /// scrubber, and it keeps going until the element is at the top or the
    /// page stops moving: in the tall iPad panel the page bottoms out with
    /// the pollutants mid-screen, and the chart still fits under them.
    private func scrollToTop(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Nothing to scroll to")
        let scrollView = app.scrollViews.containing(NSPredicate(format: "label == %@", element.label)).firstMatch
        let window = app.windows.firstMatch.frame
        let target = window.minY + window.height * 0.17
        for _ in 0..<8 {
            let y = element.frame.minY
            guard y > target + 20 else { return }
            let distance = min(y - target, window.height * 0.5)
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.8))
            let end = start.withOffset(CGVector(dx: 0, dy: -distance))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
            settle(seconds: 1)
            guard abs(element.frame.minY - y) > 2 else { return }
        }
    }

    /// The alerts card FOX-25 put under the reading: present, off, and
    /// without the two-station cap caption and locked switches it shows
    /// until OneSignal has answered (FOX-37 M3). Fails the run rather than
    /// capture a station page that isn't what the app shows.
    private func assertAlertsCardOffAndUnlocked() {
        let title = isChinese ? "空品通知" : "Air quality alerts"
        let off = isChinese ? "未開啟" : "Off"
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", title))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "No alerts card on the station page")
        XCTAssertTrue(card.label.hasSuffix(off), "Alerts card isn't off: \(card.label)")

        let cap = app.staticTexts[isChinese ? "最多只能設定 2 個測站" : "You can only enable at most for 2 stations"]
        let unlocked = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: cap)
        wait(for: [unlocked], timeout: 30)
        XCTAssertFalse(cap.exists, "Alerts card still shows the two-station cap")
    }

    /// Location and tracking prompts are allowed (index 1 in either
    /// language); a notification prompt is turned down (index 0), so a
    /// capture never registers this simulator for push.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 5) else { return }
            let isNotifications = alert.label.localizedCaseInsensitiveContains("notification")
                || alert.label.contains("通知")
            let buttons = alert.buttons
            buttons.element(boundBy: isNotifications ? 0 : min(1, buttons.count - 1)).tap()
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
