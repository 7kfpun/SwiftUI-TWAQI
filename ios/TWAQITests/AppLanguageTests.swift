//
//  AppLanguageTests.swift
//  TWAQITests
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class AppLanguageTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var originalStandard: Any?

    override func setUp() {
        super.setUp()
        suiteName = "AppLanguageTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        originalStandard = UserDefaults.standard.object(forKey: AppLanguage.defaultsKey)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        if let originalStandard = originalStandard {
            UserDefaults.standard.set(originalStandard, forKey: AppLanguage.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguage.defaultsKey)
        }
        super.tearDown()
    }

    // MARK: - Persistence

    func testDefaultsToSystem() {
        XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
        XCTAssertEqual(SettingsStore(defaults: defaults).appLanguage, .system)
    }

    func testSettingsStorePersistsChoice() {
        let settings = SettingsStore(defaults: defaults)
        settings.appLanguage = .english
        XCTAssertEqual(defaults.string(forKey: AppLanguage.defaultsKey), "en")
        XCTAssertEqual(AppLanguage.stored(in: defaults), .english)
        // A new store over the same defaults reads it back.
        XCTAssertEqual(SettingsStore(defaults: defaults).appLanguage, .english)

        settings.appLanguage = .traditionalChinese
        XCTAssertEqual(AppLanguage.stored(in: defaults), .traditionalChinese)

        settings.appLanguage = .system
        XCTAssertNil(defaults.string(forKey: AppLanguage.defaultsKey))
        XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
    }

    func testUnknownStoredValueFallsBackToSystem() {
        defaults.set("klingon", forKey: AppLanguage.defaultsKey)
        XCTAssertEqual(AppLanguage.stored(in: defaults), .system)
    }

    // MARK: - Widget mirror

    func testMirrorWritesTheChoiceAndSystemRemovesIt() {
        XCTAssertTrue(AppLanguage.mirror(.traditionalChinese, to: defaults))
        XCTAssertEqual(defaults.string(forKey: AppLanguage.defaultsKey), "zh-Hant")
        // Same value again: nothing to write, no timeline reload.
        XCTAssertFalse(AppLanguage.mirror(.traditionalChinese, to: defaults))

        XCTAssertTrue(AppLanguage.mirror(.english, to: defaults))
        XCTAssertEqual(AppLanguage.stored(in: defaults), .english)

        XCTAssertTrue(AppLanguage.mirror(.system, to: defaults))
        XCTAssertNil(defaults.string(forKey: AppLanguage.defaultsKey))
        XCTAssertFalse(AppLanguage.mirror(.system, to: defaults))
    }

    func testExtensionReadsTheMirrorAndTheAppItsOwnDefaults() throws {
        let sharedSuite = "AppLanguageTests.shared.\(UUID().uuidString)"
        let shared = try XCTUnwrap(UserDefaults(suiteName: sharedSuite))
        defer { shared.removePersistentDomain(forName: sharedSuite) }

        // Chinese chosen under Help, mirrored for the widget.
        defaults.set(AppLanguage.traditionalChinese.rawValue, forKey: AppLanguage.defaultsKey)
        AppLanguage.mirror(.traditionalChinese, to: shared)
        XCTAssertEqual(AppLanguage.current(own: defaults, shared: shared, isExtension: false), .traditionalChinese)
        // The widget's own defaults never hold a choice.
        let widgetOwn = try XCTUnwrap(UserDefaults(suiteName: "AppLanguageTests.widget.\(UUID().uuidString)"))
        XCTAssertEqual(AppLanguage.current(own: widgetOwn, shared: shared, isExtension: true), .traditionalChinese)

        // A stale mirror never overrides the app's own choice.
        defaults.removeObject(forKey: AppLanguage.defaultsKey)
        XCTAssertEqual(AppLanguage.current(own: defaults, shared: shared, isExtension: false), .system)
    }

    func testSettingsStoreMirrorsTheChoiceForTheWidget() {
        let original = AppLanguage.stored(in: AppLanguage.shared)
        defer { AppLanguage.mirror(original, to: AppLanguage.shared) }

        let settings = SettingsStore(defaults: defaults)
        settings.appLanguage = .traditionalChinese
        XCTAssertEqual(AppLanguage.stored(in: AppLanguage.shared), .traditionalChinese)
        settings.appLanguage = .system
        XCTAssertEqual(AppLanguage.stored(in: AppLanguage.shared), .system)
    }

    // MARK: - Locale

    func testLocaleResolution() {
        let chineseSystem = Locale(identifier: "zh_Hant_TW")
        let englishSystem = Locale(identifier: "en_US")

        XCTAssertEqual(AppLanguage.system.locale(system: chineseSystem), chineseSystem)
        XCTAssertEqual(AppLanguage.english.locale(system: chineseSystem).identifier, "en")
        XCTAssertEqual(AppLanguage.traditionalChinese.locale(system: englishSystem).identifier, "zh-Hant")

        XCTAssertFalse(AppLanguage.english.locale(system: chineseSystem).isChinese)
        XCTAssertTrue(AppLanguage.traditionalChinese.locale(system: englishSystem).isChinese)
        XCTAssertTrue(AppLanguage.system.locale(system: chineseSystem).isChinese)
    }

    func testLocaleIsChineseFollowsOverride() {
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.defaultsKey)
        XCTAssertFalse(Locale.isChinese)
        XCTAssertEqual(Locale.app.identifier, "en")

        UserDefaults.standard.set(AppLanguage.traditionalChinese.rawValue, forKey: AppLanguage.defaultsKey)
        XCTAssertTrue(Locale.isChinese)
    }

    func testLocalizedFollowsOverride() {
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.defaultsKey)
        XCTAssertEqual("Help.help".localized, "Help")

        UserDefaults.standard.set(AppLanguage.traditionalChinese.rawValue, forKey: AppLanguage.defaultsKey)
        XCTAssertNotEqual("Help.help".localized, "Help")
        XCTAssertNotEqual("Help.help".localized, "Help.help")
    }

    // MARK: - Translation rules

    func testChineseUISkipsTranslation() {
        XCTAssertNil(OnDeviceTranslation.target(for: Locale(identifier: "zh-Hant")))
        XCTAssertNil(OnDeviceTranslation.target(for: Locale(identifier: "zh_Hant_TW")))
        XCTAssertEqual(OnDeviceTranslation.target(for: Locale(identifier: "en")), "en")

        UserDefaults.standard.set(AppLanguage.traditionalChinese.rawValue, forKey: AppLanguage.defaultsKey)
        XCTAssertNil(OnDeviceTranslation.target)

        // Even with a translation cached, a Chinese UI shows the original.
        let text = "新北市淡水區中正東路 42 巷 6 號 \(UUID().uuidString)"
        OnDeviceTranslation.store("No. 6, Ln. 42", for: text, target: "en")
        XCTAssertEqual(OnDeviceTranslation.display(text), text)

        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.defaultsKey)
        XCTAssertEqual(OnDeviceTranslation.display(text), "No. 6, Ln. 42")
    }

    func testTargetIsTheBareLanguageCode() {
        // System English and Help → English share one cache and one pack check.
        XCTAssertEqual(OnDeviceTranslation.target(for: Locale(identifier: "en_US")), "en")
        XCTAssertEqual(OnDeviceTranslation.target(for: Locale(identifier: "en_GB")), "en")
        XCTAssertEqual(OnDeviceTranslation.target(for: Locale(identifier: "en")), "en")
        XCTAssertEqual(OnDeviceTranslation.target(for: Locale(identifier: "ja_JP")), "ja")
        XCTAssertNil(OnDeviceTranslation.target(for: Locale(identifier: "zh-Hans")))
        XCTAssertNil(OnDeviceTranslation.target(for: Locale(identifier: "zh_Hant_TW")))

        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.defaultsKey)
        XCTAssertEqual(OnDeviceTranslation.target, "en")
    }

    func testChangingLanguageClearsTranslations() {
        let text = "板橋區\(UUID().uuidString)"
        OnDeviceTranslation.store("Banqiao District", for: text, target: "en")
        XCTAssertEqual(OnDeviceTranslation.cached(text, target: "en"), "Banqiao District")

        SettingsStore(defaults: defaults).appLanguage = .english
        XCTAssertNil(OnDeviceTranslation.cached(text, target: "en"))
    }

    func testOnlyTextWithChineseIsSent() {
        XCTAssertEqual(
            OnDeviceTranslation.translatable(["板橋區", "Banqiao", "板橋區", "", "42-6"]),
            ["板橋區"]
        )
    }

    func testTownshipComesFromThePlaceTable() throws {
        let json = """
        {"station_id": 1, "lat": 25, "lon": 121, "aqi": 50, "pm25": 1, "pm10": 1, "no2": 1,
         "so2": 1, "co": 1, "o3": 1, "wind_direction": 0, "wind_speed": 0,
         "publish_time": "2026-10-31T16:00:00", "name": {"zh": "板橋", "en": "Banqiao"},
         "address": {"zh": "新北市板橋區文化路一段25號"},
         "additional_info": {"county": {"zh": "新北市", "en": "New Taipei City"},
                             "township": {"zh": "板橋區"}}}
        """
        let pollutant = try JSONDecoder().decode(Pollutant.self, from: Data(json.utf8))

        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.defaultsKey)
        XCTAssertEqual(pollutant.displayLocality, "板橋區, New Taipei City")
        XCTAssertEqual(
            pollutant.displayLocality(township: TaiwanPlaceNames.displayTownship),
            "Banqiao District, New Taipei City"
        )
    }

    func testPlaceNamesAreOfficialNotMachineTranslated() {
        XCTAssertEqual(TaiwanPlaceNames.township("大安區"), "Da'an District")
        XCTAssertEqual(TaiwanPlaceNames.township("新店區"), "Xindian District")
        XCTAssertEqual(TaiwanPlaceNames.county("台北市"), "Taipei City")
        XCTAssertEqual(TaiwanPlaceNames.county("臺北市"), "Taipei City")
        // Unknown names stay in Chinese.
        XCTAssertEqual(TaiwanPlaceNames.displayTownship("某某區"), "某某區")
        XCTAssertNil(TaiwanPlaceNames.township("某某區"))
        XCTAssertEqual(TaiwanPlaceNames.townships.count, 357)
        XCTAssertEqual(TaiwanPlaceNames.counties.count, 22)
    }

    // MARK: - Forecast, a sentence at a time

    func testSegmentsRoundTrip() {
        let text = "1. 今日東北季風影響。2. 明日風速減弱，午後臭氧易累積！\n後天轉好"
        let segments = OnDeviceTranslation.segments(text)
        XCTAssertEqual(segments, ["1. 今日東北季風影響。", "2. 明日風速減弱，午後臭氧易累積！", "\n", "後天轉好"])
        XCTAssertEqual(segments.joined(), text)
    }

    func testLeadingSegmentsCoverTheVisibleLines() {
        let segments = ["一二三四五。", "六七八九十。", "甲乙丙。"]
        XCTAssertEqual(OnDeviceTranslation.leadingSegments(segments, characters: 1), ["一二三四五。"])
        XCTAssertEqual(OnDeviceTranslation.leadingSegments(segments, characters: 7), ["一二三四五。", "六七八九十。"])
        XCTAssertEqual(OnDeviceTranslation.leadingSegments(segments, characters: 1_000), segments)
    }

    func testPartlyTranslatedForecastReadsInOrder() {
        let tag = UUID().uuidString
        let first = "今日普通。\(tag)"
        let second = "明日良好。\(tag)"
        let segments = [first, second]

        // Nothing translated: exactly the original.
        XCTAssertEqual(OnDeviceTranslation.display(segments: segments, target: "en"), first + second)

        // Visible part first: English, then the untranslated rest.
        OnDeviceTranslation.store("Moderate today.", for: first, target: "en")
        XCTAssertEqual(OnDeviceTranslation.display(segments: segments, target: "en"), "Moderate today. \(second)")

        // After expanding, all of it.
        OnDeviceTranslation.store("Good tomorrow.", for: second, target: "en")
        XCTAssertEqual(OnDeviceTranslation.display(segments: segments, target: "en"), "Moderate today. Good tomorrow.")

        // A Chinese UI never swaps anything in.
        XCTAssertEqual(OnDeviceTranslation.display(segments: segments, target: nil), first + second)
    }

    func testTranslatedSegmentKeepsLineBreak() {
        let tag = UUID().uuidString
        let line = "標題\(tag)\n"
        OnDeviceTranslation.store("Title", for: line, target: "en")
        XCTAssertEqual(OnDeviceTranslation.display(segments: [line, "Next"], target: "en"), "Title\nNext")
    }
}
