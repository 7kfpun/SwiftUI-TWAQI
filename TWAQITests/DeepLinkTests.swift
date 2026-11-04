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

    // MARK: - Station (FOX-74)

    func testStationURLRoundTrips() throws {
        let url = try XCTUnwrap(DeepLink.stationURL(stationId: 126, source: .control))
        XCTAssertEqual(url.absoluteString, "twaqi://station?id=126&source=control")
        XCTAssertEqual(DeepLink(url: url), .station(id: 126, source: .control))
        XCTAssertEqual(DeepLink(url: try XCTUnwrap(DeepLink.stationURL(stationId: 7, source: .shortcut))), .station(id: 7, source: .shortcut))
    }

    func testStationWithoutOrWithUnknownSourceIsStillAStation() throws {
        XCTAssertEqual(DeepLink(url: try url("twaqi://station?id=126")), .station(id: 126, source: .deepLink))
        XCTAssertEqual(DeepLink(url: try url("TWAQI://STATION?id=126&source=new")), .station(id: 126, source: .deepLink))
    }

    func testStationWithoutAValidIdIsNotALink() throws {
        for string in ["twaqi://station", "twaqi://station?id=", "twaqi://station?id=abc", "twaqi://station?id=0", "twaqi://station?id=-3"] {
            XCTAssertNil(DeepLink(url: try url(string)), string)
        }
    }

    func testStationRoutesWithOrWithoutPro() throws {
        let url = try url("twaqi://station?id=126&source=control")
        XCTAssertEqual(DeepLink.route(url, isPro: false), .station(id: 126, source: .control))
        XCTAssertEqual(DeepLink.route(url, isPro: true), .station(id: 126, source: .control))
    }

    func testRouterOpensTheLinkedStation() throws {
        let router = AppRouter()

        XCTAssertTrue(router.open(try url("twaqi://station?id=126&source=control"), isPro: true))
        XCTAssertEqual(router.openedStation, AppRouter.OpenedStation(id: 126))
        XCTAssertFalse(router.showingPro)
    }

    // MARK: - Router

    func testRouterOpensProWithTheLinksSource() throws {
        let router = AppRouter()

        XCTAssertTrue(router.open(try url("twaqi://pro?source=widget_locked"), isPro: false))
        XCTAssertTrue(router.showingPro)
        XCTAssertEqual(router.proSource, .widgetLocked)
    }

    func testRouterIgnoresProURLWhenAlreadyPro() throws {
        let router = AppRouter()

        XCTAssertFalse(router.open(try url("twaqi://pro?source=widget_locked"), isPro: true))
        XCTAssertFalse(router.showingPro)
        XCTAssertEqual(router.proSource, .deepLink)
    }

    func testRouterIgnoresUnknownURL() throws {
        let router = AppRouter()

        XCTAssertFalse(router.open(try url("twaqi://station/126"), isPro: false))
        XCTAssertFalse(router.open(try url("https://example.com/pro"), isPro: false))
        XCTAssertFalse(router.showingPro)
    }
}
