//
//  MapAdviceTests.swift
//  TWAQITests
//
//  TWAQ-13: one line of advice for the AQI level on the map card and station header.
//

import XCTest
@testable import Taiwan_Air

final class MapAdviceTests: XCTestCase {
    private func strings(_ language: String) throws -> [String: String] {
        let path = try XCTUnwrap(Bundle(for: Self.self).path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language)
            ?? Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language))
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    func testEveryLevelMapsToItsOwnKey() {
        let keys = AirStatuses.getShowAllCases().map { $0.adviceKey }
        XCTAssertEqual(keys, [
            "AirStatus.general_public_guidance_good",
            "AirStatus.general_public_guidance_moderate",
            "AirStatus.general_public_guidance_unhealthyforsensitivegroup",
            "AirStatus.general_public_guidance_unhealthy",
            "AirStatus.general_public_guidance_veryunhealthy",
            "AirStatus.general_public_guidance_hazardous",
        ])
    }

    func testUnknownLevelHasNoAdvice() {
        XCTAssertNil(AirStatuses.unknown.adviceKey)
    }

    func testEveryLevelHasEnglishAndTraditionalChineseText() throws {
        for language in ["en", "zh-Hant"] {
            let table = try strings(language)
            for status in AirStatuses.getShowAllCases() {
                let key = try XCTUnwrap(status.adviceKey)
                let text = try XCTUnwrap(table[key], "\(language) \(key)")
                XCTAssertFalse(text.isEmpty, "\(language) \(key)")
            }
            XCTAssertNotNil(table["Help.show_advice"], language)
        }
    }

    func testAdviceFollowsTheAqiBands() {
        let samples: [(Double, AirStatuses)] = [(30, .good), (70, .moderate), (120, .unhealthyforsensitivegroup),
                                                (170, .unhealthy), (250, .veryunhealthy), (350, .hazardous)]
        for (aqi, expected) in samples {
            XCTAssertEqual(AirStatuses.checkAirStatus(airIndexType: .aqi, value: aqi).adviceKey, expected.adviceKey)
        }
    }

    func testCardHeightAddsOneRowPerLine() {
        let base = ClosestStationView.preferredSize.height
        XCTAssertEqual(ClosestStationView.height(hasWeather: false, hasHint: false, hasAdvice: false), base)
        XCTAssertEqual(ClosestStationView.height(hasWeather: true, hasHint: false, hasAdvice: false), ClosestStationView.heightWithWeather)
        XCTAssertEqual(ClosestStationView.height(hasWeather: false, hasHint: false, hasAdvice: true),
                       ClosestStationView.topHeightWithWeather + ClosestStationView.adviceRowHeight)
        XCTAssertEqual(ClosestStationView.height(hasWeather: true, hasHint: true, hasAdvice: true),
                       ClosestStationView.heightWithWeather + ClosestStationView.adviceRowHeight + ClosestStationView.hintRowHeight)
        // A hint only shows under the weather row.
        XCTAssertEqual(ClosestStationView.height(hasWeather: false, hasHint: true, hasAdvice: false), base)
    }

    func testAdviceIsOnByDefaultAndCanBeSwitchedOff() {
        let suite = "MapAdviceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.showsAdvice)
        store.showsAdvice = false
        XCTAssertFalse(store.showsAdvice)
        store.showsAdvice = true
        XCTAssertTrue(store.showsAdvice)
    }

    func testCardClipsALongLineToOneLine() {
        let card = ClosestStationView()
        card.advice = String(repeating: "Avoid outdoor activities and keep doors and windows closed. ", count: 3)
        let label = Mirror(reflecting: card).children.first { $0.label == "adviceLabel" }?.value as? UILabel
        XCTAssertEqual(label?.numberOfLines, 1)
        XCTAssertEqual(label?.lineBreakMode, .byTruncatingTail)
        XCTAssertEqual(label?.isHidden, false)
        card.advice = nil
        XCTAssertEqual(label?.isHidden, true)
    }
}
