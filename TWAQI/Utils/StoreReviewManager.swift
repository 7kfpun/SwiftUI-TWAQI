//
//  StoreReviewManager.swift
//  TWAQI
//
//  Created by kf on 20/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation
import StoreKit

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

        TrackingManager.logEvent(.reviewRequested, parameters: ["app_open_count": appOpenCount])
        StoreReviewHelper().requestReview()
    }

    fileprivate func requestReview() {
        if #available(iOS 10.3, *) {
            SKStoreReviewController.requestReview()
        }
    }
}
