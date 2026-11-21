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

/// TWAQ-11: tapping the map's top-left card opens the details panel.
/// Needs the network (live stations). Set `TEST_RUNNER_CARD_SHOT_DIR` to write
/// screenshots and `TEST_RUNNER_CARD_LANGUAGE` (en / zh-Hant) to pick the language.
final class MapCardTapUITests: XCTestCase {
    func testTappingTheCardOpensDetails() throws {
        continueAfterFailure = false
        let language = ProcessInfo.processInfo.environment["CARD_LANGUAGE"] ?? "en"
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboardingCompleted", "YES",
            "-onboardingLegacyInstall", "NO",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language.hasPrefix("zh") ? "zh_TW" : "en_US",
        ]
        app.launch()

        let label = language.hasPrefix("zh") ? "此處空氣品質，開啟詳細資料" : "Air quality here, opens details"
        let card = app.buttons[label]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "The card is one button")
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: card)
        waitForExpectations(timeout: 30)

        shot("\(language)-1-map-card")
        card.tap()

        // The panel is a sheet with a navigation bar; the card is behind it.
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        sleep(3)
        shot("\(language)-2-details")
    }

    private func shot(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["CARD_SHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}

/// TWAQ-12: the details panel opened from the map card shows the next-24-hours
/// strip. Needs the network (live stations, forecast, weather). Set
/// `TEST_RUNNER_STRIP_SHOT_DIR` to write screenshots and
/// `TEST_RUNNER_STRIP_LANGUAGE` (en / zh-Hant) to pick the language.
final class ForecastStripUITests: XCTestCase {
    func testDetailsShowTheForecastStrip() throws {
        continueAfterFailure = false
        let language = ProcessInfo.processInfo.environment["STRIP_LANGUAGE"] ?? "en"
        let chinese = language.hasPrefix("zh")
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboardingCompleted", "YES",
            "-onboardingLegacyInstall", "NO",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", chinese ? "zh_TW" : "en_US",
        ]
        app.launch()

        let card = app.buttons[chinese ? "此處空氣品質，開啟詳細資料" : "Air quality here, opens details"]
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: card)
        waitForExpectations(timeout: 30)
        card.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))

        // The strip is one VoiceOver element that starts with its title.
        let title = chinese ? "未來 24 小時" : "Next 24 hours"
        let strip = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        for _ in 0..<8 where !strip.exists || !strip.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(strip.waitForExistence(timeout: 20), "the strip is on the details page")
        // Bring the whole strip into view, clear of the ad banner, for the screenshot.
        let screen = app.windows.firstMatch.frame
        for _ in 0..<8 where strip.frame.minY > screen.height * 0.24 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        }
        sleep(2)
        shot("\(language)-strip")
    }

    private func shot(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["STRIP_SHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
