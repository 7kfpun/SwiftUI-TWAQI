//
//  HelpSectionOrderTests.swift
//  TWAQITests
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

/// FOX-68: Premium is the first section of the Help tab for free users.
final class HelpSectionOrderTests: XCTestCase {
    func testFreeUserSeesPremiumFirst() {
        XCTAssertEqual(
            HelpSection.order(isPro: false, developerMode: false),
            [.purchase, .doNotDisturb, .language, .appearance, .welcome, .contact, .widgetsAndWatch, .definition, .dataSources, .about]
        )
    }

    /// FOX-88: Data sources shows for everyone, Pro or not.
    func testDataSourcesSectionAlwaysShows() {
        XCTAssertTrue(HelpSection.order(isPro: true, developerMode: false).contains(.dataSources))
        XCTAssertTrue(HelpSection.order(isPro: false, developerMode: true).contains(.dataSources))
    }

    func testProUserHasNoPremiumSection() {
        let order = HelpSection.order(isPro: true, developerMode: false)

        XCTAssertFalse(order.contains(.purchase))
        XCTAssertEqual(order.first, .doNotDisturb)
    }

    func testDeveloperSectionIsLastAndOnlyInDeveloperMode() {
        XCTAssertFalse(HelpSection.order(isPro: false, developerMode: false).contains(.developer))
        XCTAssertEqual(HelpSection.order(isPro: false, developerMode: true).last, .developer)
        XCTAssertEqual(HelpSection.order(isPro: true, developerMode: true).last, .developer)
    }
}

/// FOX-118: Help's "Privacy settings" shows only where UMP requires it.
final class PrivacySettingsVisibilityTests: XCTestCase {
    func testOnlyRequiredStatusShowsTheRow() {
        XCTAssertTrue(ConsentManager.showsPrivacyOptions(.required))
        XCTAssertFalse(ConsentManager.showsPrivacyOptions(.notRequired))
        XCTAssertFalse(ConsentManager.showsPrivacyOptions(.unknown))
    }

    func testHelpSectionFollowsTheRequirement() {
        XCTAssertFalse(HelpSection.order(isPro: false, developerMode: false).contains(.privacy))
        XCTAssertTrue(HelpSection.order(isPro: false, developerMode: false, privacyOptionsRequired: true).contains(.privacy))
        XCTAssertFalse(HelpSection.order(isPro: true, developerMode: false, privacyOptionsRequired: true).contains(.privacy))
    }

    func testPrivacyStringsExistInEnglishAndChinese() throws {
        for language in ["en", "zh-Hant"] {
            let bundle = Bundle(for: HelpViewModel.self)
            let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
            let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
            for key in ["Help.privacy", "Help.privacy_settings"] {
                XCTAssertFalse(table[key]?.isEmpty ?? true, "\(key) missing in \(language)")
            }
        }
    }
}

/// FOX-88: Help → Data sources names every source the screens used to label.
final class DataSourcesTests: XCTestCase {
    private func strings(_ language: String) throws -> [String: String] {
        let bundle = Bundle(for: HelpViewModel.self)
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    func testEverySourceIsLocalizedInEnglishAndChinese() throws {
        for language in ["en", "zh-Hant"] {
            let table = try strings(language)
            let keys = DataSource.allCases.flatMap { [$0.titleKey, $0.detailKey] }
                + ["DataSources.header", "DataSources.footer", "DataSources.licence_title"]
            for key in keys {
                let value = table[key]
                XCTAssertNotNil(value, "\(key) missing in \(language)")
                XCTAssertFalse(value?.isEmpty ?? true, "\(key) empty in \(language)")
            }
        }
    }

    func testEverySourceLinksOverHTTPS() {
        for source in DataSource.allCases {
            XCTAssertEqual(source.url.scheme, "https", source.rawValue)
            XCTAssertNotNil(source.url.host, source.rawValue)
        }
        XCTAssertEqual(DataSource.licenceURL.scheme, "https")
    }

    /// The screens no longer carry source labels, so their keys are gone.
    func testOnScreenSourceKeysAreRemoved() throws {
        for language in ["en", "zh-Hant"] {
            let table = try strings(language)
            for key in ["Details.cam_source", "Forecast.source", "Weather.source"] {
                XCTAssertNil(table[key], "\(key) still in \(language)")
            }
        }
    }
}
