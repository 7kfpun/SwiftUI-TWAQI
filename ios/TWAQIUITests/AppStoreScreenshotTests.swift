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
        // with it the notification prompt), `onboardingLegacyInstall` keeps
        // the launch-time prompt off even on a simulator with an older
        // install, the camera keys frame the whole island, the favourites
        // are seeded without touching alerts, and the last two pick the
        // language.
        app.launchArguments = [
            "-pro", "YES",
            "-onboardingCompleted", "YES",
            "-onboardingLegacyInstall", "NO",
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
    /// buttons, slowly so the scroll view doesn't coast past it, then makes
    /// sure no text is left under those buttons.
    ///
    /// Since FOX-25 the alerts card and health advice sit above the
    /// pollutants, so they start well below the fold. Each drag starts in
    /// the scroll view's right gutter, clear of the switches and the cam
    /// scrubber. The page can bottom out before `element` reaches the
    /// buttons (in the iPad panel it stops with the pollutants mid-screen),
    /// which can leave a line of text under them; the page is then pulled
    /// back down until that text clears them. The chart still fits under
    /// the pollutants either way.
    private func scrollToTop(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Nothing to scroll to")
        let scrollView = app.scrollViews.containing(NSPredicate(format: "label == %@", element.label)).firstMatch
        let overlays = floatingControls(over: scrollView)
        let floor = overlays.map(\.maxY).max() ?? scrollView.frame.minY
        let gap: CGFloat = 16

        // Up: the pollutants to just under the buttons, or as far as the
        // page goes.
        for _ in 0..<8 {
            let y = element.frame.minY
            guard y > floor + gap + 8 else { break }
            drag(scrollView, by: -min(y - floor - gap, app.windows.firstMatch.frame.height * 0.5))
            guard abs(element.frame.minY - y) > 2 else { break }
        }

        // Down: until no text is under a button. Each pull moves the lowest
        // covered text just below the button over it; text further up can
        // then slide under, so check again.
        for _ in 0..<6 {
            guard let covered = textUnder(overlays, in: scrollView) else { return }
            drag(scrollView, by: covered.overlay.maxY + gap - covered.text.minY)
        }
        if let covered = textUnder(overlays, in: scrollView) {
            XCTFail("\"\(covered.label)\" at \(covered.text) is still under a button at \(covered.overlay)")
        }
    }

    /// What floats over the top of the station page: the close, share and
    /// favourite buttons, and in a wide window the tab bar.
    private func floatingControls(over scrollView: XCUIElement) -> [CGRect] {
        let page = scrollView.frame
        let named = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "關閉", "Share", "分享"]))
        let controls = app.navigationBars.buttons.allElementsBoundByIndex
            + named.allElementsBoundByIndex
            + app.tabBars.allElementsBoundByIndex
        let frames = controls
            .map(\.frame)
            // Small controls near the top, not a container that spans the window.
            .filter { !$0.isEmpty && $0.intersects(page) && $0.minY < page.midY && $0.height < page.height / 8 }
        XCTAssertFalse(frames.isEmpty, "No close or share button over the station page")
        return frames
    }

    /// The lowest piece of text in `scrollView` that one of `overlays`
    /// covers, if any, with the overlay that covers it. A page that can't be
    /// read fails the run: no answer is not the same as no covered text.
    private func textUnder(_ overlays: [CGRect], in scrollView: XCUIElement)
        -> (label: String, text: CGRect, overlay: CGRect)? {
        let root: XCUIElementSnapshot
        do {
            root = try scrollView.snapshot()
        } catch {
            XCTFail("Couldn't read the station page to check for covered text: \(error)")
            return nil
        }
        var lowest: (label: String, text: CGRect, overlay: CGRect)?
        var pending = root.children
        while let node = pending.popLast() {
            pending.append(contentsOf: node.children)
            // Leaves with a label are what a reader sees as text: labels,
            // switches with their caption, combined rows. The cam frame and
            // the scrubber aren't text, so they may sit under the buttons.
            guard node.children.isEmpty, !node.label.isEmpty,
                  node.elementType != .image, node.elementType != .slider else { continue }
            let text = node.frame
            // The glass circle round a toolbar glyph reaches ~8 pt past
            // the frame XCUITest reports for the button.
            guard let overlay = overlays.first(where: { $0.insetBy(dx: -8, dy: -8).intersects(text) }) else { continue }
            if text.minY > lowest?.text.minY ?? -.greatestFiniteMagnitude {
                lowest = (node.label, text, overlay)
            }
        }
        return lowest
    }

    /// Moves the page by `distance` points (negative is up), slowly and with
    /// a hold at the end so it doesn't coast. A drag loses its first few
    /// points to the touch slop, so a short move overshoots and comes back
    /// by the same detour; the two losses cancel.
    private func drag(_ scrollView: XCUIElement, by distance: CGFloat) {
        let detour: CGFloat = abs(distance) < 60 ? (distance < 0 ? -60 : 60) : 0
        for step in detour == 0 ? [distance] : [distance + detour, -detour] {
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: step < 0 ? 0.8 : 0.3))
            let end = start.withOffset(CGVector(dx: 0, dy: step))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
            settle(seconds: 1)
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
