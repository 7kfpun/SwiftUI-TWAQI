//
//  MapAdviceTests.swift
//  TWAQITests
//
//  TWAQ-13: one line of advice for the AQI level on the map card and station header.
//

import SwiftUI
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

    /// The card is a fixed-size map overlay with fixed fonts, like its other rows, so
    /// the largest Dynamic Type size must neither grow the line nor push it out of its row.
    func testAdviceStaysOneClippedLineAtLargestDynamicType() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("trait overrides need iOS 17") }
        let card = ClosestStationView()
        card.translatesAutoresizingMaskIntoConstraints = true
        card.frame = CGRect(origin: .zero, size: CGSize(
            width: ClosestStationView.preferredSize.width,
            height: ClosestStationView.height(hasWeather: false, hasHint: false, hasAdvice: true)
        ))
        card.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        card.advice = "Avoid outdoor activities and keep doors and windows closed"
        card.layoutIfNeeded()
        let label = try XCTUnwrap(Mirror(reflecting: card).children.first { $0.label == "adviceLabel" }?.value as? UILabel)
        XCTAssertEqual(label.numberOfLines, 1)
        XCTAssertLessThanOrEqual(label.frame.height, ClosestStationView.adviceRowHeight)
        XCTAssertLessThanOrEqual(label.frame.maxX, card.bounds.width)
        XCTAssertLessThanOrEqual(label.intrinsicContentSize.height, ClosestStationView.adviceRowHeight)
    }

    /// The station header scales with Dynamic Type; the advice must stay one line there:
    /// a very long sentence is exactly as tall as a short one.
    func testHeaderAdviceStaysOneLineAtLargestDynamicType() {
        func height(_ advice: String) -> CGFloat {
            let header = StationHeaderView(title: "Songshan", locality: nil, area: nil, stationType: .general,
                                           aqi: 170, publishTime: nil, advice: advice)
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
            let host = UIHostingController(rootView: header)
            return host.sizeThatFits(in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)).height
        }
        let short = height("Reduce outdoor activities")
        let long = height(String(repeating: "Avoid outdoor activities and keep doors and windows closed. ", count: 4))
        XCTAssertEqual(short, long, accuracy: 0.5)
        XCTAssertGreaterThan(short, height(""), "the line is shown")
    }

    /// Draws the card for every level, in both languages, when
    /// `ADVICE_SHOT_DIR` is set (passed as `TEST_RUNNER_ADVICE_SHOT_DIR`, for PR
    /// screenshots). Always checks that the advice line lies inside its card.
    func testCardForEveryLevel() throws {
        let dir = ProcessInfo.processInfo.environment["ADVICE_SHOT_DIR"]
        let originalLanguage = UserDefaults.standard.string(forKey: AppLanguage.defaultsKey)
        defer {
            if let originalLanguage { UserDefaults.standard.set(originalLanguage, forKey: AppLanguage.defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: AppLanguage.defaultsKey) }
        }
        let samples: [(Double, AirStatuses)] = [(30, .good), (70, .moderate), (120, .unhealthyforsensitivegroup),
                                                (170, .unhealthy), (250, .veryunhealthy), (350, .hazardous)]
        for language in [AppLanguage.english, .traditionalChinese] {
            UserDefaults.standard.set(language.localeIdentifier, forKey: AppLanguage.defaultsKey)
            let board = UIView(frame: CGRect(x: 0, y: 0, width: 3 * 252, height: 2 * 136))
            board.backgroundColor = .systemGray5
            for (index, sample) in samples.enumerated() {
                let card = ClosestStationView()
                card.translatesAutoresizingMaskIntoConstraints = true
                card.stationName = "Songshan"
                card.locality = "Xinyi District, Taipei"
                card.status = "AirStatus.\(sample.1.rawValue)".localized
                card.aqi = "AQI \(Int(sample.0))"
                card.aqiColor = UIColor(rgb: Int(sample.1.getColor()))
                card.aqiForegroundColor = UIColor(rgb: Int(sample.1.getForegroundColor()))
                card.image = UIImage(named: sample.1.getImage())
                card.advice = sample.1.adviceKey?.localized
                card.isEnabled = true
                let height = ClosestStationView.height(hasWeather: false, hasHint: false, hasAdvice: true)
                card.frame = CGRect(x: 10 + CGFloat(index % 3) * 252, y: 10 + CGFloat(index / 3) * 136,
                                    width: ClosestStationView.preferredSize.width, height: height)
                board.addSubview(card)
                card.layoutIfNeeded()
                let label = try XCTUnwrap(Mirror(reflecting: card).children.first { $0.label == "adviceLabel" }?.value as? UILabel)
                XCTAssertTrue(card.bounds.contains(label.frame), "\(language) \(sample.1)")
            }
            board.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: board.bounds).image { context in
                board.layer.render(in: context.cgContext)
            }
            if let dir, let data = image.pngData() {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("twaq-13-\(language == .english ? "en" : "zh-Hant")-card-levels.png"))
            }
        }
    }
}
