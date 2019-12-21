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

    static func incrementAppOpenedCount() { // called from appdelegate didfinishLaunchingWithOptions:
        guard var appOpenCount = UserDefaults.standard.value(forKey: Keys.appOpenedCount) as? Int else {
            UserDefaults.standard.set(1, forKey: Keys.appOpenedCount)
            return
        }
        appOpenCount += 1
        UserDefaults.standard.set(appOpenCount, forKey: Keys.appOpenedCount)
    }

    static func checkAndAskForReview() { // call this whenever appropriate
        // this will not be shown everytime. Apple has some internal logic on how to show this.
        guard let appOpenCount = UserDefaults.standard.value(forKey: Keys.appOpenedCount) as? Int else {
            UserDefaults.standard.set(1, forKey: Keys.appOpenedCount)
            return
        }

        switch appOpenCount {
        case 10, 30, 60:
            StoreReviewHelper().requestReview()
        case _ where appOpenCount % 100 == 0 :
            StoreReviewHelper().requestReview()
        default:
            print("App run count is : \(appOpenCount)")
        }
    }

    fileprivate func requestReview() {
        if #available(iOS 10.3, *) {
            SKStoreReviewController.requestReview()
        }
    }
}
