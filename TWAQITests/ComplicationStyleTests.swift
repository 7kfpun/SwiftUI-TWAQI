//
//  ComplicationStyleTests.swift
//  TWAQITests
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest

/// The watch complication's free / Pro split (FOX-63): the face is free
/// without its number, every other style needs Pro.
final class ComplicationStyleTests: XCTestCase {
    func testOnlyTheFaceIsFree() {
        let free = ComplicationStyle.allCases.filter { !$0.isPro }
        XCTAssertEqual(free, [.face])
    }

    func testProUnlocksEveryStyleWithItsNumber() {
        for style in ComplicationStyle.allCases {
            let access = ComplicationAccess(style: style, isPro: true)
            XCTAssertEqual(access, .full, "\(style)")
            XCTAssertTrue(access.showsNumber, "\(style)")
        }
    }

    func testFreeFaceShowsItsReadingWithoutTheNumber() {
        let access = ComplicationAccess(style: .face, isPro: false)
        XCTAssertEqual(access, .faceOnly)
        XCTAssertFalse(access.showsNumber)
    }

    func testFreeReaderSeesALockOnEveryProStyle() {
        for style in [ComplicationStyle.labelled, .numberOnly, .status] {
            let access = ComplicationAccess(style: style, isPro: false)
            XCTAssertEqual(access, .locked, "\(style)")
            XCTAssertFalse(access.showsNumber, "\(style)")
        }
    }

    /// Saved complications store the raw value; renaming one would reset
    /// every complication already on a face.
    func testRawValuesAreStable() {
        XCTAssertEqual(ComplicationStyle.allCases.map(\.rawValue), ["labelled", "numberOnly", "face", "status"])
    }
}
