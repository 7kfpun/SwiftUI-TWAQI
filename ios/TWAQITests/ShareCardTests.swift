//
//  ShareCardTests.swift
//  TWAQITests
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

@MainActor
final class ShareCardTests: XCTestCase {

    private func card(aqi: Double, title: String = "Keelung", shape: ShareCardShape = .feed) -> ShareCardView {
        ShareCardView(
            title: title,
            locality: "Xinyi District, Keelung City",
            aqi: aqi,
            pollutant: nil,
            publishTime: "2026-08-07T22:00:00",
            shape: shape
        )
    }

    private func lproj(_ identifier: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: identifier, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    // MARK: - Shapes

    /// 4:5 for a feed post, 9:16 for a story, 1:1 for a chat, all 1080 px wide.
    func testShapePixelSizes() {
        XCTAssertEqual(ShareCardShape.feed.pixelSize, CGSize(width: 1080, height: 1350))
        XCTAssertEqual(ShareCardShape.story.pixelSize, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(ShareCardShape.square.pixelSize, CGSize(width: 1080, height: 1080))
    }

    /// The picker's order, and the values analytics and the stored choice use.
    func testShapeOrderAndRawValues() {
        XCTAssertEqual(ShareCardShape.allCases, [.feed, .story, .square])
        XCTAssertEqual(ShareCardShape.allCases.map(\.rawValue), ["4x5", "9x16", "1x1"])
    }

    func testCardDefaultsToFeed() {
        let card = ShareCardView(title: "Keelung", locality: nil, aqi: 54, pollutant: nil, publishTime: nil)
        XCTAssertEqual(card.shape, .feed)
    }

    func testRendersEachShapeAtItsPixelSize() throws {
        for shape in ShareCardShape.allCases {
            let image = try XCTUnwrap(ShareCardSharing.render(card(aqi: 54, shape: shape)))
            XCTAssertEqual(image.size.width * image.scale, shape.pixelSize.width, "\(shape)")
            XCTAssertEqual(image.size.height * image.scale, shape.pixelSize.height, "\(shape)")
        }
    }

    /// A long station name shrinks or wraps rather than pushing the card taller.
    func testLongTitleKeepsCardSize() throws {
        let long = String(repeating: "Very long station name ", count: 6)
        for shape in ShareCardShape.allCases {
            let image = try XCTUnwrap(ShareCardSharing.render(card(aqi: 162, title: long, shape: shape)))
            XCTAssertEqual(image.size.height * image.scale, shape.pixelSize.height, "\(shape)")
        }
    }

    // MARK: - Analytics

    func testAnalyticsParameters() {
        let opened = ShareCardSharing.parameters(card: card(aqi: 54.7, shape: .story), stationId: 12)
        XCTAssertEqual(opened["stationId"] as? Int, 12)
        XCTAssertEqual(opened["aqi"] as? Int, 54)
        XCTAssertEqual(opened["shape"] as? String, "9x16")
        XCTAssertNil(opened["action"])

        for (action, value) in [(ShareCardAction.share, "share"), (.save, "save"), (.cancel, "cancel")] {
            let parameters = ShareCardSharing.parameters(card: card(aqi: 54, shape: .square), stationId: 12, action: action)
            XCTAssertEqual(parameters["action"] as? String, value)
            XCTAssertEqual(parameters["shape"] as? String, "1x1")
        }
    }

    // MARK: - Session (cancel)

    func testClosingUntouchedSessionCancelsOnce() {
        let session = ShareCardSession()
        session.appeared()
        XCTAssertTrue(session.disappeared())
        XCTAssertFalse(session.disappeared())
    }

    func testShareThenFailedSaveIsNotACancel() {
        let session = ShareCardSession()
        session.appeared()
        session.shared()
        session.saveStarted()
        XCTAssertFalse(session.saveFinished(saved: false))
        XCTAssertFalse(session.disappeared())
        XCTAssertTrue(session.isCommitted)
    }

    func testFailedSaveAfterSuccessfulSaveIsNotACancel() {
        let session = ShareCardSession()
        session.appeared()
        session.saveStarted()
        session.saveStarted()
        XCTAssertFalse(session.saveFinished(saved: true))
        XCTAssertFalse(session.saveFinished(saved: false))
        XCTAssertFalse(session.disappeared())
    }

    func testDeniedSaveThenCloseCancels() {
        let session = ShareCardSession()
        session.appeared()
        session.saveStarted()
        XCTAssertFalse(session.saveFinished(saved: false))
        XCTAssertTrue(session.disappeared())
    }

    func testCloseDuringSaveThatFailsCancelsFromTheSave() {
        let session = ShareCardSession()
        session.appeared()
        session.saveStarted()
        XCTAssertFalse(session.disappeared())
        XCTAssertTrue(session.saveFinished(saved: false))
    }

    func testCloseDuringSaveThatSucceedsIsNotACancel() {
        let session = ShareCardSession()
        session.appeared()
        session.saveStarted()
        XCTAssertFalse(session.disappeared())
        XCTAssertFalse(session.saveFinished(saved: true))
    }

    func testReappearingAfterDisappearDoesNotCancelEarly() {
        let session = ShareCardSession()
        session.appeared()
        session.saveStarted()
        XCTAssertFalse(session.disappeared())
        session.appeared()
        XCTAssertFalse(session.saveFinished(saved: false))
        XCTAssertTrue(session.disappeared())
    }

    // MARK: - Message

    func testMessageInEnglish() throws {
        let bundle = try lproj("en")
        XCTAssertEqual(
            ShareCardSharing.message(title: "Keelung", aqi: 54, bundle: bundle),
            "Keelung: AQI 54, Moderate — via Taiwan Air"
        )
        XCTAssertEqual(
            ShareCardSharing.shareText(title: "Keelung", aqi: 54, bundle: bundle),
            "Keelung: AQI 54, Moderate — via Taiwan Air\nhttps://apps.apple.com/app/id1286516443"
        )
    }

    func testMessageInTraditionalChinese() throws {
        let bundle = try lproj("zh-Hant")
        XCTAssertEqual(
            ShareCardSharing.message(title: "基隆", aqi: 120.6, bundle: bundle),
            "基隆：AQI 120，對敏感族群不健康 — 來自 Taiwan Air"
        )
    }
}
