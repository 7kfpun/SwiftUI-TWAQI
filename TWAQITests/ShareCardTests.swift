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

    private func card(aqi: Double, title: String = "Keelung") -> ShareCardView {
        ShareCardView(
            title: title,
            locality: "Xinyi District, Keelung City",
            aqi: aqi,
            pollutant: nil,
            publishTime: "2026-08-07T22:00:00"
        )
    }

    /// 1080 × 1350 is the 4:5 size feeds and stories take without cropping.
    func testRendersAtFourByFive() throws {
        let image = try XCTUnwrap(ShareCardSharing.render(card(aqi: 54)))
        XCTAssertEqual(image.size.width * image.scale, 1080)
        XCTAssertEqual(image.size.height * image.scale, 1350)
    }

    /// A long station name shrinks rather than pushing the card taller.
    func testLongTitleKeepsCardSize() throws {
        let long = String(repeating: "Very long station name ", count: 6)
        let image = try XCTUnwrap(ShareCardSharing.render(card(aqi: 162, title: long)))
        XCTAssertEqual(image.size.height * image.scale, 1350)
    }
}
