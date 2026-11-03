//
//  Onboarding.swift
//  TWAQI
//
//  Created by kf on 2/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import CoreLocation
import Foundation

/// The welcome flow (FOX-34): opens by itself once for every user, fresh
/// installs and updates alike (FOX-49), and again whenever it is opened from
/// Help.
enum Onboarding {
    /// Posted on the main thread when the flow is finished or skipped. The map
    /// holds back its location request until then, so the system prompts
    /// don't stack over the flow.
    static let didFinish = Notification.Name("Onboarding.didFinish")

    /// The flow opened by itself on this launch and isn't finished yet.
    /// Decided in `AppDelegate` before the flow marks itself shown, so the
    /// launch-time prompts (location, notifications, review) stay out of its
    /// way. Main thread only.
    static var isOpenAtLaunch = false

    /// A scene has taken the flow that opens by itself on this launch.
    /// Main thread only; tests reset it.
    static var launchFlowClaimed = false

    /// Whether a connecting scene opens the flow by itself: only the first
    /// one on a launch that shows it, so two windows restored together on
    /// iPad don't both open it and one going away can't release the hold
    /// while the other still shows it.
    static func claimLaunchFlow(showsOnLaunch: Bool) -> Bool {
        guard showsOnLaunch, !launchFlowClaimed else { return false }
        launchFlowClaimed = true
        return true
    }

    /// Ends the launch-time hold, once: clears `isOpenAtLaunch` and posts
    /// `didFinish` so the held prompts go ahead. Called when the flow is
    /// finished or skipped, and when the scene showing it goes away without
    /// either, so a hold can't outlive the flow. Main thread only.
    static func releaseLaunchHold(notificationCenter: NotificationCenter = .default) {
        guard isOpenAtLaunch else { return }
        isOpenAtLaunch = false
        notificationCenter.post(name: didFinish, object: nil)
    }

    /// The flow was finished or skipped. Only the run that opened by itself
    /// at launch ends the hold: Help can run the flow in a second iPad window
    /// while the first still shows the launch run, and finishing that one
    /// mustn't let the held prompts out over it.
    static func flowEnded(isLaunchFlow: Bool, notificationCenter: NotificationCenter = .default) {
        guard isLaunchFlow else { return }
        releaseLaunchHold(notificationCenter: notificationCenter)
    }

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

/// Which version of the welcome flow has opened by itself, in the app's own
/// defaults.
struct OnboardingStore {
    /// The flow's version. Raise it to open a reworked flow by itself once
    /// more for everyone; nothing else has to change.
    static let currentVersion = 1

    enum Keys {
        /// The highest flow version that has opened by itself. Set when it is
        /// presented, not when it is finished, so quitting or skipping it
        /// counts as shown.
        static let shownVersion = "onboardingShownVersion"
        /// Set once the first launch of an onboarding build has looked at
        /// whether the install is older than the flow.
        static let installChecked = "onboardingInstallChecked"
        /// The install ran before the flow existed.
        static let legacyInstall = "onboardingLegacyInstall"
        /// FOX-34 builds: finished or skipped, or an older install marked so
        /// without seeing the flow. Read once to carry its answer over.
        static let completed = "onboardingCompleted"
    }

    private let defaults: UserDefaults
    private let currentVersion: Int

    init(defaults: UserDefaults = .standard, currentVersion: Int = OnboardingStore.currentVersion) {
        self.defaults = defaults
        self.currentVersion = currentVersion
    }

    /// The highest flow version that has opened by itself; 0 for none.
    var shownVersion: Int {
        defaults.integer(forKey: Keys.shownVersion)
    }

    /// The install pre-dates the flow. Such installs keep the launch-time
    /// notification prompt they always had (a no-op once answered); fresh
    /// installs are asked on the flow's notifications step only.
    var isLegacyInstall: Bool {
        defaults.bool(forKey: Keys.legacyInstall)
    }

    /// Whether the flow should open by itself at launch: this version of it
    /// never has, on any earlier launch.
    var showsOnLaunch: Bool { shownVersion < currentVersion }

    /// Whether `AppDelegate` may ask for notifications at launch. Never on a
    /// launch that opens the flow, which asks on its own step.
    var promptsForPushAtLaunch: Bool { isLegacyInstall && !showsOnLaunch }

    /// The flow opened by itself: it won't again until the version is raised.
    /// Help's manual runs don't call this. Returns whether this call recorded
    /// it, so a repeated `onAppear` is counted once.
    @discardableResult
    func markShown() -> Bool {
        guard shownVersion < currentVersion else { return false }
        defaults.set(currentVersion, forKey: Keys.shownVersion)
        return true
    }

    /// Run once per launch, before this launch is counted anywhere.
    ///
    /// Notes whether the install pre-dates the flow, on the first launch of
    /// an onboarding build only. Such installs are walked through it too.
    ///
    /// A FOX-34 build marked a flow as `completed` when it was finished or
    /// skipped (version 1 was shown), or, for an older install, without
    /// showing it (it still has to be).
    func prepareForLaunch(hasLaunchedBefore: Bool) {
        if !defaults.bool(forKey: Keys.installChecked) {
            defaults.set(true, forKey: Keys.installChecked)
            if hasLaunchedBefore && !defaults.bool(forKey: Keys.completed) {
                defaults.set(true, forKey: Keys.legacyInstall)
            }
        }

        if defaults.object(forKey: Keys.shownVersion) == nil,
           defaults.bool(forKey: Keys.completed), !isLegacyInstall {
            defaults.set(1, forKey: Keys.shownVersion)
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
