//
//  HelpTabUITests.swift
//  TWAQIUITests
//
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest

/// FOX-180: every Help row must take a tap, and the ad banner must sit below
/// the list rather than over a row. Runs on a free (not Pro) install so the
/// banner is present. Set `HELP_SHOT_DIR` (via `TEST_RUNNER_HELP_SHOT_DIR`)
/// to also write screenshots there.
final class HelpTabUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        let language = ProcessInfo.processInfo.environment["HELP_LANGUAGE"] ?? "en"
        app.launchArguments = [
            "-onboardingCompleted", "YES",
            "-onboardingLegacyInstall", "NO",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language.hasPrefix("zh") ? "zh_TW" : "en_US",
        ]
        app.launch()
        let tabs = app.tabBars.buttons
        XCTAssertTrue(tabs.firstMatch.waitForExistence(timeout: 20))
        tabs.element(boundBy: tabs.count - 1).tap()
    }

    private func shot(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["HELP_SHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private var list: XCUIElement {
        app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
    }

    private func row(_ labels: [String]) -> XCUIElement {
        list.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    /// Scrolls until `element` can take a tap: on screen and not under the banner or tab bar.
    private func scrollToHittable(_ element: XCUIElement) {
        var tries = 0
        while !(element.exists && element.isHittable) && tries < 12 {
            list.swipeUp(velocity: .slow)
            tries += 1
        }
        if !(element.exists && element.isHittable) {
            for _ in 0..<12 where !(element.exists && element.isHittable) { list.swipeDown(velocity: .slow) }
        }
    }

    func testHelpRowsTakeTaps() throws {
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        shot("help-initial")

        // Navigation rows: each must open a page and come back.
        let pushRows: [[String]] = [
            ["Feedback / Contact us", "意見回饋 / 聯絡我們"],
            ["Interested to be our Business Partner?", "想成為我們的合作夥伴嗎？"],
            ["Home Screen & Lock Screen widgets", "主畫面與鎖定畫面小工具"],
            ["Apple Watch"],
            ["Siri, Shortcuts & Control Center", "Siri、捷徑與控制中心"],
        ]
        for labels in pushRows {
            let target = row(labels)
            scrollToHittable(target)
            XCTAssertTrue(target.exists, "missing row \(labels)")
            XCTAssertTrue(target.isHittable, "row \(labels) is covered")
            target.tap()
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 5), "row \(labels) did not open")
            back.tap()
        }

        // The welcome guide opens full screen.
        let welcome = row(["Show welcome guide", "顯示歡迎導覽"])
        scrollToHittable(welcome)
        XCTAssertTrue(welcome.isHittable, "welcome row is covered")
        welcome.tap()
        let skip = app.buttons.matching(NSPredicate(format: "label IN %@", ["Skip", "略過"])).firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "welcome guide did not open")
        skip.tap()

        // Pickers: open the menu, pick an entry, and the list answers again.
        for labels in [["Appearance", "外觀"], ["Language", "語言"]] {
            let picker = list.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", labels[0], labels.last!)).firstMatch
            scrollToHittable(picker)
            XCTAssertTrue(picker.isHittable, "picker \(labels) is covered")
            picker.tap()
            shot("help-choices-\(labels[0])")
            // The choices open as a page of their own: pick the first, which pops back.
            let choices = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "System default", "跟隨系統"))
            XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 5), "choices for \(labels) did not open")
            // The list underneath keeps its own copy of the current value; take the visible one.
            guard let entry = choices.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
                return XCTFail("choices for \(labels) did not open")
            }
            entry.tap()
            // Choosing may pop the page itself; if not, go back.
            if !picker.waitForExistence(timeout: 3) || !picker.isHittable {
                app.navigationBars.buttons.element(boundBy: 0).tap()
            }
            XCTAssertTrue(picker.waitForExistence(timeout: 5), "list did not come back after choosing")
            // A stuck-open menu would swallow this tap.
            let feedback = row(["Feedback / Contact us", "意見回饋 / 聯絡我們"])
            scrollToHittable(feedback)
            feedback.tap()
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 5), "choices for \(labels) left the list stuck")
            back.tap()
        }

        // The last page of the list ends above the banner.
        for _ in 0..<8 { list.swipeUp(velocity: .fast) }
        shot("help-scrolled-bottom")
    }
}
