//
//  CooperateServiceTests.swift
//  TWAQITests
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import XCTest
@testable import Taiwan_Air

final class CooperateServiceTests: XCTestCase {

    private func submission(
        jobTitle: String? = nil,
        phone: String? = nil,
        website: String? = nil
    ) -> CooperateSubmission {
        CooperateSubmission.make(
            cooperationType: .dataApi,
            company: "  Fox Co. \n",
            name: " Ann ",
            jobTitle: jobTitle,
            email: " ann@example.com ",
            phone: phone,
            website: website,
            message: "  Embed AQI on our site \n"
        )
    }

    private func json(_ submission: CooperateSubmission) throws -> [String: Any] {
        let data = try JSONEncoder().encode(submission)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testMakeTrimsTextAndDropsBlankOptionals() {
        let made = submission(jobTitle: "  ", phone: "\n", website: " ")

        XCTAssertEqual(made.company, "Fox Co.")
        XCTAssertEqual(made.name, "Ann")
        XCTAssertEqual(made.email, "ann@example.com")
        XCTAssertEqual(made.message, "Embed AQI on our site")
        XCTAssertEqual(made.cooperationType, "data_api")
        XCTAssertNil(made.jobTitle)
        XCTAssertNil(made.phone)
        XCTAssertNil(made.website)
    }

    func testMakeFillsHiddenDeviceFields() {
        let made = submission()

        XCTAssertEqual(made.platform, "ios")
        XCTAssertFalse(made.deviceModel?.isEmpty ?? true)
        XCTAssertFalse(made.osVersion?.isEmpty ?? true)
        XCTAssertFalse(made.locale?.isEmpty ?? true)
        XCTAssertEqual(made.metaJson?["app_platform"], "ios")
        XCTAssertNotNil(made.metaJson?["bundle_id"])
    }

    func testEncodesDirectusFieldNames() throws {
        let object = try json(submission(jobTitle: "CEO", phone: "02-1234-5678", website: "fox.example"))

        XCTAssertEqual(Set(object.keys), [
            "cooperation_type", "company", "name", "job_title", "email", "phone", "website", "message",
            "platform", "app_version", "device_model", "os_version", "locale", "meta_json", "archived",
        ])
        XCTAssertEqual(object["job_title"] as? String, "CEO")
        XCTAssertNotNil(object["meta_json"] as? [String: String])
    }

    func testOmitsBlankOptionalsAndSendsNotArchived() throws {
        let object = try json(submission())

        XCTAssertNil(object["job_title"])
        XCTAssertNil(object["phone"])
        XCTAssertNil(object["website"])
        // Created live; archiving is the soft delete, done in Directus.
        XCTAssertEqual(object["archived"] as? Bool, false)
        // Preset on the server; the app never sends it.
        XCTAssertNil(object["status"])
    }

    func testTypeRawValuesMatchDirectusChoices() {
        XCTAssertEqual(
            CooperationType.allCases.map(\.rawValue),
            ["advertising", "data_api", "sponsorship", "media", "other"]
        )
    }

    func testRequestPostsToCollectionWithCooperateToken() throws {
        let request = try XCTUnwrap(CooperateService.makeRequest(
            baseURL: "https://cms.example.com",
            cooperateToken: "coop-token",
            feedbackToken: "feedback-token",
            submission: submission()
        ))

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://cms.example.com/items/twaqi_cooperate")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer coop-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["company"] as? String, "Fox Co.")
    }

    func testRequestFallsBackToFeedbackToken() throws {
        for cooperateToken in [nil, "", "  "] as [String?] {
            let request = try XCTUnwrap(CooperateService.makeRequest(
                baseURL: "https://cms.example.com",
                cooperateToken: cooperateToken,
                feedbackToken: "feedback-token",
                submission: submission()
            ))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer feedback-token")
        }
    }

    func testRequestNeedsUrlAndSomeToken() {
        XCTAssertNil(CooperateService.makeRequest(
            baseURL: "https://cms.example.com", cooperateToken: nil, feedbackToken: "", submission: submission()
        ))
        XCTAssertNil(CooperateService.makeRequest(
            baseURL: "", cooperateToken: "t", feedbackToken: "t", submission: submission()
        ))
    }
}
