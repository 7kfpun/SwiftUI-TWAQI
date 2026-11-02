//
//  Onboarding.swift
//  TWAQI
//
//  Created by kf on 2/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import Foundation

/// The welcome flow (FOX-34): shown once on a fresh install, and again
/// whenever it is opened from Help.
enum Onboarding {
    /// Posted on the main thread when the flow is finished or skipped. The map
    /// holds back its location request until then, so the system prompts
    /// don't stack over the flow.
    static let didFinish = Notification.Name("Onboarding.didFinish")

    /// The steps, in order. Location is asked for on `.location` only, and
    /// notifications on `.notifications` only.
    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case location
        case closestStation
        case notifications
        case doNotDisturb
        case dataSource
        case premium

        var id: Int { rawValue }

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }
        var isLast: Bool { next == nil }
    }
}

/// Whether the welcome flow has been seen, in the app's own defaults.
struct OnboardingStore {
    enum Keys {
        static let completed = "onboardingCompleted"
        /// Set once the first launch of an onboarding build has looked at
        /// whether the install is older than the flow.
        static let installChecked = "onboardingInstallChecked"
        /// The install ran before the flow existed, and was marked complete
        /// without seeing it.
        static let legacyInstall = "onboardingLegacyInstall"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isCompleted: Bool {
        defaults.bool(forKey: Keys.completed)
    }

    /// The install pre-dates the flow. Such installs keep the launch-time
    /// notification prompt they always had (a no-op once answered); fresh
    /// installs are asked on the flow's notifications step only.
    var isLegacyInstall: Bool {
        defaults.bool(forKey: Keys.legacyInstall)
    }

    /// Whether the flow should open by itself at launch.
    var showsOnLaunch: Bool { !isCompleted }

    /// Whether `AppDelegate` may ask for notifications at launch.
    var promptsForPushAtLaunch: Bool { isLegacyInstall }

    /// Finished or skipped: the flow won't open by itself again.
    func markCompleted() {
        defaults.set(true, forKey: Keys.completed)
    }

    /// Run once per launch, before this launch is counted anywhere.
    ///
    /// Someone updating from a build without the flow has used the app
    /// already; they are not walked through it (Help has it). Decided on the
    /// first launch of an onboarding build only, so a fresh install that
    /// quits mid-flow still gets the flow on its next launch.
    func adoptExistingInstall(hasLaunchedBefore: Bool) {
        guard !defaults.bool(forKey: Keys.installChecked) else { return }
        defaults.set(true, forKey: Keys.installChecked)

        if hasLaunchedBefore && !isCompleted {
            defaults.set(true, forKey: Keys.completed)
            defaults.set(true, forKey: Keys.legacyInstall)
        }
    }
}

/// The station the flow suggests as a first favourite.
struct OnboardingClosestStation: Equatable {
    let pollutant: Pollutant
    /// No location: the station nearest 中正, the Watch app's default.
    let isFallback: Bool

    /// The station nearest `location`, or, without one, nearest the same
    /// 中正 point the Watch app falls back to (`WatchAPI.defaultLocation`).
    static func resolve(location: CLLocation?, in stations: Pollutants) -> OnboardingClosestStation? {
        guard let pollutant = WatchAPI.closest(to: location ?? WatchAPI.defaultLocation, in: stations) else {
            return nil
        }
        return OnboardingClosestStation(pollutant: pollutant, isFallback: location == nil)
    }
}
