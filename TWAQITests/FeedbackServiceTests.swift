//
//  FeedbackServiceTests.swift
//  TWAQITests
//
//  Created by kf on 29/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class FeedbackServiceTests: XCTestCase {

    private func submission(
        rating: Int = 4,
        otherFeedback: String? = nil,
        name: String? = nil,
        email: String = "me@example.com"
    ) -> FeedbackSubmission {
        FeedbackSubmission.make(
            rating: rating,
            message: "  Add PM1 \n",
            otherFeedback: otherFeedback,
            interviewInterest: true,
            name: name,
            email: email
        )
    }

    private func json(_ submission: FeedbackSubmission) throws -> [String: Any] {
        let data = try JSONEncoder().encode(submission)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testMakeTrimsTextAndDropsBlankOptionals() {
        let made = submission(otherFeedback: " \n ", name: "  ", email: " me@example.com ")

        XCTAssertEqual(made.message, "Add PM1")
        XCTAssertEqual(made.email, "me@example.com")
        XCTAssertNil(made.otherFeedback)
        XCTAssertNil(made.name)
        XCTAssertTrue(made.interviewInterest)
    }

    func testMakeFillsHiddenDeviceFields() {
        let made = submission()

        XCTAssertFalse(made.deviceModel?.isEmpty ?? true)
        XCTAssertFalse(made.osVersion?.isEmpty ?? true)
        XCTAssertFalse(made.locale?.isEmpty ?? true)
        XCTAssertEqual(made.metaJson?["app_platform"], "ios")
        XCTAssertNotNil(made.metaJson?["device_idiom"])
        XCTAssertNotNil(made.metaJson?["bundle_id"])
    }

    func testMakeSetsPlatformFromBuild() throws {
        let made = submission()

        // Tests run in the iOS app, so the automatic value is "ios".
        XCTAssertEqual(FeedbackPlatform.suggested, .ios)
        XCTAssertEqual(made.platform, FeedbackPlatform.suggested.rawValue)
        XCTAssertEqual(try json(made)["platform"] as? String, "ios")
    }

    func testMakeClampsRating() {
        XCTAssertEqual(submission(rating: 9).rating, 5)
        XCTAssertEqual(submission(rating: 0).rating, 1)
    }

    func testEncodesDirectusFieldNames() throws {
        let object = try json(submission(otherFeedback: "Widget is slow", name: "Ann"))

        XCTAssertEqual(Set(object.keys), [
            "platform", "rating", "message", "other_feedback", "interview_interest",
            "name", "email", "app_version", "device_model", "os_version", "locale", "meta_json",
        ])
        XCTAssertEqual(object["interview_interest"] as? Bool, true)
        XCTAssertEqual(object["other_feedback"] as? String, "Widget is slow")
        XCTAssertNotNil(object["meta_json"] as? [String: String])
    }

    func testOmitsBlankOptionalsAndServerFields() throws {
        let object = try json(submission())

        XCTAssertNil(object["other_feedback"])
        XCTAssertNil(object["name"])
        // Set on the server; the app must never send them.
        XCTAssertNil(object["status"])
        XCTAssertNil(object["archived"])
    }

    func testEmailValidation() {
        XCTAssertTrue(FeedbackSubmission.isValidEmail("me@example.com"))
        XCTAssertTrue(FeedbackSubmission.isValidEmail(" me@example.com "))
        XCTAssertFalse(FeedbackSubmission.isValidEmail(""))
        XCTAssertFalse(FeedbackSubmission.isValidEmail("me@example"))
        XCTAssertFalse(FeedbackSubmission.isValidEmail("me@@example.com"))
        XCTAssertFalse(FeedbackSubmission.isValidEmail("m e@example.com"))
    }

    func testRequestPostsToCollectionWithBearerToken() throws {
        let request = try XCTUnwrap(FeedbackService.makeRequest(
            baseURL: "https://cms.example.com",
            token: "test-token",
            submission: submission()
        ))

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://cms.example.com/items/twaqi_feedback")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["message"] as? String, "Add PM1")
    }

    func testRequestNeedsUrlAndToken() {
        XCTAssertNil(FeedbackService.makeRequest(baseURL: "https://cms.example.com", token: "", submission: submission()))
        XCTAssertNil(FeedbackService.makeRequest(baseURL: "https://cms.example.com", token: nil, submission: submission()))
        XCTAssertNil(FeedbackService.makeRequest(baseURL: "", token: "t", submission: submission()))
    }
}
