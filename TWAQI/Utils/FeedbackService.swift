//
//  FeedbackService.swift
//  TWAQI
//
//  Created by kf on 29/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation
import SwiftUI
import UIKit

/// The Directus `platform` value. The app sets it from the build it runs in;
/// the user is never asked. `android` stays so the enum mirrors the field.
enum FeedbackPlatform: String, CaseIterable {
    case ios
    case android
    case other

    /// iPhone and iPad builds send `ios`; visionOS builds send `other`.
    static var suggested: FeedbackPlatform {
        #if os(visionOS)
        return .other
        #else
        return .ios
        #endif
    }
}

/// One item in the Directus `twaqi_feedback` collection. The app only ever
/// creates items; `status` and `archived` are preset on the server.
/// Nil fields are left out of the JSON.
struct FeedbackSubmission: Encodable, Equatable {
    // Set by the app from the build, never shown.
    var platform: String

    // What the user fills in.
    var rating: Int
    var message: String
    var otherFeedback: String?
    var interviewInterest: Bool
    var name: String?
    var email: String

    // Filled in by the app, never shown.
    var appVersion: String?
    var deviceModel: String?
    var osVersion: String?
    var locale: String?
    var metaJson: [String: String]?

    enum CodingKeys: String, CodingKey {
        case platform, rating, message, name, email, locale
        case otherFeedback = "other_feedback"
        case interviewInterest = "interview_interest"
        case appVersion = "app_version"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case metaJson = "meta_json"
    }

    /// Adds the app and device fields, including `platform`, to what the user
    /// typed. Text is trimmed, and blank optional text is sent as absent
    /// rather than as "".
    static func make(
        rating: Int,
        message: String,
        otherFeedback: String?,
        interviewInterest: Bool,
        name: String?,
        email: String,
        bundle: Bundle = .main
    ) -> FeedbackSubmission {
        let info = bundle.infoDictionary
        return FeedbackSubmission(
            platform: FeedbackPlatform.suggested.rawValue,
            rating: min(max(rating, 1), 5),
            message: trimmed(message) ?? "",
            otherFeedback: trimmed(otherFeedback),
            interviewInterest: interviewInterest,
            name: trimmed(name),
            email: trimmed(email) ?? "",
            appVersion: info?["CFBundleShortVersionString"] as? String,
            deviceModel: currentDeviceModel,
            osVersion: UIDevice.current.systemVersion,
            locale: Locale.current.identifier,
            metaJson: clientMeta(bundle: bundle)
        )
    }

    /// The `meta_json` details sent with every form the app posts to
    /// Directus (feedback and cooperate).
    static func clientMeta(bundle: Bundle = .main) -> [String: String] {
        var meta: [String: String] = [:]
        meta["bundle_id"] = bundle.bundleIdentifier
        meta["build"] = bundle.infoDictionary?["CFBundleVersion"] as? String
        meta["app_platform"] = appPlatform
        meta["device_idiom"] = deviceIdiom
        meta["app_language"] = bundle.preferredLocalizations.first
        meta["preferred_languages"] = Locale.preferredLanguages.prefix(3).joined(separator: ",")
        meta["time_zone"] = TimeZone.current.identifier
        // Per-install and per-vendor; resets when every app from us is removed.
        meta["anonymous_id"] = UIDevice.current.identifierForVendor?.uuidString
        return meta
    }

    /// Trimmed text, or nil when blank, so optional fields are left out of
    /// the JSON rather than sent as "".
    static func trimmed(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    /// The OS this build runs on. Finer than `platform`, which has no
    /// visionOS value.
    static var appPlatform: String {
        #if os(visionOS)
        return "visionos"
        #else
        return "ios"
        #endif
    }

    static var deviceIdiom: String {
        #if os(visionOS)
        return "vision"
        #else
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return "phone"
        case .pad:
            return "pad"
        case .mac:
            return "mac"
        default:
            return "unknown"
        }
        #endif
    }

    /// The hardware identifier, e.g. "iPhone16,2", which tells models apart
    /// where `UIDevice.model` only says "iPhone".
    static var currentDeviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafeBytes(of: &systemInfo.machine) { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    /// Loose on purpose: catches typos like a missing "@" or domain, and
    /// leaves the rest to the server.
    static func isValidEmail(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2
            && !parts[0].isEmpty
            && parts[1].contains(".")
            && !parts[1].hasPrefix(".")
            && !parts[1].hasSuffix(".")
            && !value.contains(where: \.isWhitespace)
    }
}

/// Why a create-only Directus form (feedback or cooperate) wasn't sent.
enum FeedbackError: Error, Equatable {
    /// The Directus URL or token is missing from the build's xcconfig.
    case notConfigured
    case offline
    case server(statusCode: Int)
    case network
}

enum FeedbackService {
    static let collectionPath = "items/twaqi_feedback"

    static func submit(
        _ submission: FeedbackSubmission,
        session: URLSession = .shared
    ) async throws {
        try await createItem(
            makeRequest(
                baseURL: getEnv("DirectusUrl"),
                token: getEnv("DirectusFeedbackToken"),
                submission: submission
            ),
            session: session
        )
    }

    static func makeRequest(
        baseURL: String?,
        token: String?,
        submission: FeedbackSubmission
    ) -> URLRequest? {
        makeCreateRequest(baseURL: baseURL, token: token, path: collectionPath, body: submission)
    }

    // MARK: - Shared create-only POST

    /// Sends a request built by `makeCreateRequest`; nil means the build has
    /// no Directus URL or token.
    static func createItem(
        _ request: URLRequest?,
        session: URLSession = .shared
    ) async throws {
        guard let request = request else {
            throw FeedbackError.notConfigured
        }

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch let error as URLError
            where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            throw FeedbackError.offline
        } catch {
            throw FeedbackError.network
        }

        // Directus answers 200 with the item, or 204 when the token cannot
        // read the collection back, which a create-only one cannot.
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackError.network
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FeedbackError.server(statusCode: http.statusCode)
        }
    }

    /// POST `body` as JSON to `path` under `baseURL` with a bearer token.
    static func makeCreateRequest<Body: Encodable>(
        baseURL: String?,
        token: String?,
        path: String,
        body: Body
    ) -> URLRequest? {
        guard let baseURL = baseURL?.trimmingCharacters(in: .whitespaces), !baseURL.isEmpty,
              let token = token?.trimmingCharacters(in: .whitespaces), !token.isEmpty,
              let base = URL(string: baseURL),
              let data = try? JSONEncoder().encode(body)
        else {
            return nil
        }

        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data
        return request
    }
}
