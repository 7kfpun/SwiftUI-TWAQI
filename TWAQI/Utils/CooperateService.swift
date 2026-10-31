//
//  CooperateService.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import UIKit

/// What the partner is interested in. Raw values are the Directus
/// `cooperation_type` dropdown choices.
enum CooperationType: String, CaseIterable, Identifiable {
    case advertising
    case dataApi = "data_api"
    case sponsorship
    case media
    case other

    var id: String { rawValue }
}

/// One item in the Directus `twaqi_cooperate` collection (business partner
/// enquiries, replacing the Airtable partner form). The app only creates
/// items: it sends `archived: false`, and an enquiry is later soft-deleted by
/// setting `archived` in Directus, never removed. `status` is preset on the
/// server. Nil fields are left out of the JSON.
struct CooperateSubmission: Encodable, Equatable {
    // What the user fills in.
    var cooperationType: String
    var company: String
    var name: String
    var jobTitle: String?
    var email: String
    var phone: String?
    var website: String?
    var message: String

    // Filled in by the app, never shown.
    var platform: String
    var appVersion: String?
    var deviceModel: String?
    var osVersion: String?
    var locale: String?
    var metaJson: [String: String]?

    /// Soft-delete flag, always false on create.
    var archived = false

    enum CodingKeys: String, CodingKey {
        case company, name, email, phone, website, message, platform, locale, archived
        case cooperationType = "cooperation_type"
        case jobTitle = "job_title"
        case appVersion = "app_version"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case metaJson = "meta_json"
    }

    /// Adds the app and device fields to what the user typed, trimming text
    /// and dropping blank optional fields.
    static func make(
        cooperationType: CooperationType,
        company: String,
        name: String,
        jobTitle: String?,
        email: String,
        phone: String?,
        website: String?,
        message: String,
        bundle: Bundle = .main
    ) -> CooperateSubmission {
        let trimmed = FeedbackSubmission.trimmed
        return CooperateSubmission(
            cooperationType: cooperationType.rawValue,
            company: trimmed(company) ?? "",
            name: trimmed(name) ?? "",
            jobTitle: trimmed(jobTitle),
            email: trimmed(email) ?? "",
            phone: trimmed(phone),
            website: trimmed(website),
            message: trimmed(message) ?? "",
            platform: FeedbackPlatform.suggested.rawValue,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
            deviceModel: FeedbackSubmission.currentDeviceModel,
            osVersion: UIDevice.current.systemVersion,
            locale: Locale.current.identifier,
            metaJson: FeedbackSubmission.clientMeta(bundle: bundle)
        )
    }
}

/// Posts partner enquiries to Directus with the same create-only pattern as
/// `FeedbackService`.
enum CooperateService {
    static let collectionPath = "items/twaqi_cooperate"

    static func submit(
        _ submission: CooperateSubmission,
        session: URLSession = .shared
    ) async throws {
        try await FeedbackService.createItem(
            makeRequest(
                baseURL: getEnv("DirectusUrl"),
                cooperateToken: getEnv("DirectusCooperateToken"),
                feedbackToken: getEnv("DirectusFeedbackToken"),
                submission: submission
            ),
            session: session
        )
    }

    /// Uses `DirectusCooperateToken` when the build sets one, else the
    /// feedback token, whose role is expected to have create on
    /// `twaqi_cooperate` too.
    static func makeRequest(
        baseURL: String?,
        cooperateToken: String?,
        feedbackToken: String?,
        submission: CooperateSubmission
    ) -> URLRequest? {
        let token = [cooperateToken, feedbackToken]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return FeedbackService.makeCreateRequest(
            baseURL: baseURL,
            token: token,
            path: collectionPath,
            body: submission
        )
    }
}
