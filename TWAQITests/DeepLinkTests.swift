//
//  DeepLinkTests.swift
//  TWAQITests
//
//  Created by kf on 2/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class DeepLinkTests: XCTestCase {
    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    // MARK: - Parsing

    func testWidgetURLRoundTrips() throws {
        let url = try XCTUnwrap(DeepLink.proURL(source: .widgetLocked))
        XCTAssertEqual(url.absoluteString, "twaqi://pro?source=widget_locked")
        XCTAssertEqual(DeepLink(url: url), .pro(source: .widgetLocked))
    }

    func testProWithoutOrWithUnknownSourceIsStillPro() throws {
        XCTAssertEqual(DeepLink(url: try url("twaqi://pro")), .pro(source: .deepLink))
        XCTAssertEqual(DeepLink(url: try url("twaqi://pro/")), .pro(source: .deepLink))
        XCTAssertEqual(DeepLink(url: try url("twaqi://pro?source=somewhere_new")), .pro(source: .deepLink))
        XCTAssertEqual(DeepLink(url: try url("TWAQI://PRO?source=widget_locked")), .pro(source: .widgetLocked))
    }

    func testUnknownURLsAreNotLinks() throws {
        for string in [
            "twaqi://",
            "twaqi://station/126",
            "twaqi://pro/extra",
            "twaqi://help?source=widget_locked",
            "https://pro?source=widget_locked",
            "https://taiwanair.wahthefox.com/pro",
            "otherapp://pro",
        ] {
            XCTAssertNil(DeepLink(url: try url(string)), string)
        }
    }

    // MARK: - Routing

    func testProURLRoutesForFreeUser() throws {
        let link = DeepLink.route(try url("twaqi://pro?source=widget_locked"), isPro: false)
        XCTAssertEqual(link, .pro(source: .widgetLocked))
    }

    func testProURLIsIgnoredForProUser() throws {
        XCTAssertNil(DeepLink.route(try url("twaqi://pro?source=widget_locked"), isPro: true))
    }

    func testUnknownURLIsIgnored() throws {
        XCTAssertNil(DeepLink.route(try url("twaqi://station/126"), isPro: false))
    }

    // MARK: - Router

    func testRouterOpensProAndLogsSource() throws {
        var logged: [ProScreenSource] = []
        let router = AppRouter { logged.append($0) }

        XCTAssertTrue(router.open(try url("twaqi://pro?source=widget_locked"), isPro: false))
        XCTAssertTrue(router.showingPro)
        XCTAssertEqual(logged, [.widgetLocked])
    }

    func testRouterIgnoresProURLWhenAlreadyPro() throws {
        var logged: [ProScreenSource] = []
        let router = AppRouter { logged.append($0) }

        XCTAssertFalse(router.open(try url("twaqi://pro?source=widget_locked"), isPro: true))
        XCTAssertFalse(router.showingPro)
        XCTAssertTrue(logged.isEmpty)
    }

    func testRouterIgnoresUnknownURL() throws {
        var logged: [ProScreenSource] = []
        let router = AppRouter { logged.append($0) }

        XCTAssertFalse(router.open(try url("twaqi://station/126"), isPro: false))
        XCTAssertFalse(router.open(try url("https://example.com/pro"), isPro: false))
        XCTAssertFalse(router.showingPro)
        XCTAssertTrue(logged.isEmpty)
    }
}
