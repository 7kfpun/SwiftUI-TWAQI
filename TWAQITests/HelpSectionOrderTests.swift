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
            [.purchase, .doNotDisturb, .language, .welcome, .contact, .widgetsAndWatch, .definition, .about]
        )
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
