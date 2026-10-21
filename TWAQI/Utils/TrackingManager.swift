//
//  TrackingManager.swift
//  TWAQI
//
//  Created by kf on 4/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import Foundation

struct TrackingManager {
    /// Per-device opt-out of analytics and crash reporting, independent of
    /// DEBUG/Release. Toggled by tapping the version row in Help 7 times, so the
    /// developer's own TestFlight/Release use stays out of production counts
    /// without a rebuild.
    private static let excludedKey = "analyticsExcluded"

    static var isExcluded: Bool {
        UserDefaults.standard.bool(forKey: excludedKey)
    }

    /// Whether this launch reports anything. Xcode runs (DEBUG) never do.
    static var isExcludedThisLaunch: Bool {
        #if DEBUG
        return true
        #else
        return isExcluded
        #endif
    }

    /// Call once, right after `FirebaseApp.configure()`.
    static func applyExclusionAtLaunch() {
        setFirebaseCollection(enabled: !isExcludedThisLaunch)
    }

    /// Persists the choice and stops or resumes Firebase immediately. Bugsnag
    /// and Sentry have no off switch once started; they follow on next launch.
    static func setExcluded(_ excluded: Bool) {
        UserDefaults.standard.set(excluded, forKey: excludedKey)
        setFirebaseCollection(enabled: !excluded)
    }

    private static func setFirebaseCollection(enabled: Bool) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.setAnalyticsCollectionEnabled(enabled)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
    }

    static func setUserProperty(key: String, value: String) {
        // Google Analytics
        Analytics.setUserProperty(value, forName: key)
    }

    static func logEvent(eventName: String, parameters: [String: Any] = [:]) {
        print("LogEvent", eventName, parameters)

        // Google Analytics log event.
        Analytics.logEvent(eventName, parameters: parameters)
    }
}
