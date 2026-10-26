//
//  ShareScreenshotTests.swift
//  TWAQIUITests
//
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest

/// Captures the App Store screenshot for the share card: a station open with
/// the share sheet showing its card. Runs on any device — iPhone, iPad or the
/// unfolded iPhone Duo.
///
/// Not part of the normal test run. Pass, via `TEST_RUNNER_`-prefixed
/// variables:
///
///   SCREENSHOT_DIR       where the PNG is written (a path on the Mac)
///   SCREENSHOT_FILE      its file name, e.g. "iPhone Duo 04.png"
///   SCREENSHOT_LANGUAGE  "en" or "zh-Hant"
final class ShareScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var outputURL: URL!
    private var isChinese = false

    override func setUpWithError() throws {
        continueAfterFailure = false

        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SCREENSHOT_DIR"], !dir.isEmpty,
              let file = env["SCREENSHOT_FILE"], !file.isEmpty else {
            throw XCTSkip("SCREENSHOT_DIR / SCREENSHOT_FILE not set")
        }
        let outputDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        outputURL = outputDir.appendingPathComponent(file)

        let language = env["SCREENSHOT_LANGUAGE"] ?? "en"
        isChinese = language.hasPrefix("zh")

        app = XCUIApplication()
        // Same launch state as DuoScreenshotTests: no ads, the whole island in
        // view, and the language for this launch only.
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

    func testCaptureShareScreenshot() throws {
        // Stands alone on the east coast, so the tap can't land on a
        // neighbour the way one in the Taipei cluster would.
        let station = isChinese ? "花蓮" : "Hualien"

        let marker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", station))
            .firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 30), "No map marker labelled \(station)")
        settle()
        marker.tap()

        // Disabled until the station's reading has loaded.
        let share = app.buttons[isChinese ? "分享" : "Share"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 15), "No share button")
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: share)
        wait(for: [enabled], timeout: 30)
        settle()

        share.tap()
        // The share sheet's own list of actions; its accessibility identifier
        // has been "ActivityListView" since iOS 13.
        let sheet = app.otherElements["ActivityListView"].firstMatch
        if !sheet.waitForExistence(timeout: 15) {
            print("SHARE-DEBUG\n\(app.debugDescription)")
            XCTFail("Share sheet did not open")
        }
        settle()
        snapshot()
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

    /// Lets data load, the card render and the sheet finish animating.
    private func settle() {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 4)
    }

    private func snapshot() {
        // On the Duo XCUIScreen.main can be the dark outer display; the
        // largest screen is the one in use everywhere.
        let screen = XCUIScreen.screens.max {
            $0.screenshot().image.size.width * $0.screenshot().image.size.height
                < $1.screenshot().image.size.width * $1.screenshot().image.size.height
        } ?? XCUIScreen.main
        let png = screen.screenshot().pngRepresentation
        XCTAssertNoThrow(try png.write(to: outputURL))

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = outputURL.lastPathComponent
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
