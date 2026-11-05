//
//  FoldLineTests.swift
//  TWAQITests
//
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

/// Where the two-pane layouts split on an unfolded iPhone Duo. A wrong answer
/// puts a pane across the hinge, or squeezes one to a sliver.
final class FoldLineTests: XCTestCase {

    /// The whole unfolded display, folding down its middle.
    private let window = CGRect(x: 0, y: 0, width: 950, height: 668)

    func testNoFoldKeepsTheLayoutsOwnSplit() {
        XCTAssertNil(FoldLine.leadingWidth(foldX: nil, in: window))
    }

    func testFullWindowSplitsOnTheFold() {
        XCTAssertEqual(FoldLine.leadingWidth(foldX: 475, in: window), 475)
    }

    func testContainerInsetFromTheWindowEdge() {
        // A container starting 40pt in (a safe area, say) ends its leading
        // pane on the same line.
        let container = CGRect(x: 40, y: 0, width: 910, height: 668)
        XCTAssertEqual(FoldLine.leadingWidth(foldX: 475, in: container), 435)
    }

    func testFoldTooCloseToAnEdgeIsIgnored() {
        // Split screen: a window that only just crosses the hinge would get
        // a pane narrower than a list row.
        let narrowRight = CGRect(x: 400, y: 0, width: 550, height: 668)
        XCTAssertNil(FoldLine.leadingWidth(foldX: 475, in: narrowRight))

        let narrowLeft = CGRect(x: 0, y: 0, width: 600, height: 668)
        XCTAssertNil(FoldLine.leadingWidth(foldX: 475, in: narrowLeft))
    }

    func testFoldOutsideTheContainerIsIgnored() {
        let container = CGRect(x: 500, y: 0, width: 450, height: 668)
        XCTAssertNil(FoldLine.leadingWidth(foldX: 475, in: container))
    }
}
