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
        #if DEBUG
        // Xcode runs report nothing, except to Firebase DebugView when the
        // scheme passes `-FIRDebugEnabled`: Firebase keeps debug-mode events
        // out of the production reports, so new events can be checked there.
        if FirebaseApp.app() != nil,
           debugViewCollectionEnabled(arguments: ProcessInfo.processInfo.arguments, isExcluded: isExcluded) {
            Analytics.setAnalyticsCollectionEnabled(true)
        }
        #endif
    }

    /// Whether a DEBUG launch sends Analytics events to DebugView: only with
    /// Firebase's debug flag, and never on a device excluded from reporting.
    static func debugViewCollectionEnabled(arguments: [String], isExcluded: Bool) -> Bool {
        !isExcluded && arguments.contains("-FIRDebugEnabled")
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

    /// Logs `event`. Names come from `AnalyticsEvent` only, so they stay
    /// consistent; with collection off (see above) Firebase drops it.
    static func logEvent(_ event: AnalyticsEvent, parameters: [String: Any] = [:]) {
        #if DEBUG
        print("LogEvent", event.rawValue, parameters)
        #endif

        Analytics.logEvent(event.rawValue, parameters: parameters)
    }

    /// The Pro screen opened, and from where: the first step of the Pro
    /// funnel. `ProView` logs it once per presentation.
    static func logProScreenOpened(source: ProScreenSource) {
        logEvent(.proScreenOpened, parameters: ["source": source.rawValue])
    }
}
