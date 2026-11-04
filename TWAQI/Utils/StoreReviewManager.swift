//
//  StoreReviewManager.swift
//  TWAQI
//
//  Created by kf on 20/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import StoreKit
import UIKit

/// What asked for the system review prompt, for `.reviewRequested`'s `source`.
enum ReviewRequestSource: String {
    /// Every `StoreReviewHelper.reviewRequestInterval` app opens.
    case appOpens = "app_opens"
    /// Right after a 4- or 5-star feedback was sent (FOX-80).
    case feedback
}

struct StoreReviewHelper {
    private enum Keys {
        static let appOpenedCount = "appOpenedCount"
    }

    /// Ask for a review every this many app opens.
    static let reviewRequestInterval = 20

    /// The app has been opened before this launch was counted.
    static var hasLaunchedBefore: Bool {
        (UserDefaults.standard.value(forKey: Keys.appOpenedCount) as? Int ?? 0) > 0
    }

    static func incrementAppOpenedCount() { // called from appdelegate didfinishLaunchingWithOptions:
        guard var appOpenCount = UserDefaults.standard.value(forKey: Keys.appOpenedCount) as? Int else {
            UserDefaults.standard.set(1, forKey: Keys.appOpenedCount)
            return
        }
        appOpenCount += 1
        UserDefaults.standard.set(appOpenCount, forKey: Keys.appOpenedCount)
    }

    /// Whether this open should request a review: opens 20, 40, 60, and so on.
    /// iOS decides whether the prompt actually shows, so asking often is fine.
    static func shouldRequestReview(appOpenCount: Int) -> Bool {
        appOpenCount > 0 && appOpenCount % reviewRequestInterval == 0
    }

    /// Lowest feedback rating (of 1–5 stars) that asks for a review.
    static let feedbackReviewMinimumRating = 4

    /// Whether a feedback sent with this rating should ask for a review:
    /// 4 or 5 stars only. Call it only once the feedback was sent.
    static func shouldRequestReview(afterFeedbackRating rating: Int) -> Bool {
        (feedbackReviewMinimumRating...5).contains(rating)
    }

    /// The App Store's write-review page, for the user-initiated
    /// "Rate on the App Store" button.
    static var writeReviewURL: URL {
        var components = URLComponents(url: ShareCardSharing.appStoreURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "action", value: "write-review")]
        return components.url!
    }

    /// Asks iOS for the review prompt after a successful feedback with
    /// `rating`, if the rating is high enough. iOS decides whether it shows.
    /// Skipped when the app has left the foreground (e.g. "Rate on the App
    /// Store" was tapped first).
    @MainActor
    static func requestReviewAfterFeedback(rating: Int) {
        guard shouldRequestReview(afterFeedbackRating: rating),
              let scene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive })
        else { return }

        TrackingManager.logEvent(
            .reviewRequested,
            parameters: ["source": ReviewRequestSource.feedback.rawValue, "rating": rating]
        )
        if #available(iOS 16.0, *) {
            AppStore.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    static func checkAndAskForReview() { // call this whenever appropriate
        // this will not be shown everytime. Apple has some internal logic on how to show this.
        guard let appOpenCount = UserDefaults.standard.value(forKey: Keys.appOpenedCount) as? Int else {
            UserDefaults.standard.set(1, forKey: Keys.appOpenedCount)
            return
        }

        guard shouldRequestReview(appOpenCount: appOpenCount) else {
            print("App run count is : \(appOpenCount)")
            return
        }

        TrackingManager.logEvent(.reviewRequested, parameters: [
            "source": ReviewRequestSource.appOpens.rawValue,
            "app_open_count": appOpenCount,
        ])
        StoreReviewHelper().requestReview()
    }

    fileprivate func requestReview() {
        if #available(iOS 10.3, *) {
            SKStoreReviewController.requestReview()
        }
    }
}
