//
//  WhatsNew.swift
//  TWAQI
//
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// The What's New popup (FOX-142): opens by itself once per marketing
/// version, after an update. The welcome flow (FOX-49) is not replayed.
enum WhatsNew {
    /// One line of a release's list. `isPro` marks a Pro feature in the
    /// bullet; the popup never links to Pro.
    struct Item: Equatable {
        let icon: String
        /// `Localizable.strings` keys.
        let titleKey: String
        let bodyKey: String
        var isPro = false
    }

    struct Release: Equatable {
        let version: String
        let items: [Item]
    }

    /// The lists, newest last. Add an entry with each release, aligned with
    /// the App Store What's New (`fastlane/metadata/*/release_notes.txt`),
    /// and its strings under `WhatsNew.<version>.*`. A version with no entry
    /// opens no popup (it is still counted as seen).
    static let releases: [Release] = [
        Release(version: "3.1.5", items: [
            Item(icon: "cloud.sun", titleKey: "WhatsNew.3_1_5.weather_title",
                 bodyKey: "WhatsNew.3_1_5.weather_body"),
            Item(icon: "hand.wave", titleKey: "WhatsNew.3_1_5.welcome_title",
                 bodyKey: "WhatsNew.3_1_5.welcome_body"),
            Item(icon: "circle.lefthalf.filled", titleKey: "WhatsNew.3_1_5.appearance_title",
                 bodyKey: "WhatsNew.3_1_5.appearance_body"),
        ]),
    ]

    static func release(for version: String) -> Release? {
        releases.first { $0.version == version }
    }

    /// The running app's marketing version.
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Numeric, dot by dot, so 3.10 is newer than 3.9 and 3.1 equals 3.1.0.
    /// A part that isn't a number counts as 0.
    static func isNewer(_ version: String, than other: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }
        let b = other.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Nothing may open over a system permission prompt that is still
    /// waiting to be asked or answered (location from the map, notifications
    /// for older installs). The launch is skipped, not counted, so the popup
    /// comes on a later one.
    static func isClearOfPermissionPrompts(locationUndetermined: Bool, notificationsUndetermined: Bool) -> Bool {
        !locationUndetermined && !notificationsUndetermined
    }

    /// A scene has taken the popup on this launch. Main thread only; tests
    /// reset it. Two iPad windows restored together don't both open it.
    static var launchClaimed = false

    static func claimLaunchPopup(shows: Bool) -> Bool {
        guard shows, !launchClaimed else { return false }
        launchClaimed = true
        return true
    }
}

/// The last marketing version whose popup was presented, in the app's own
/// defaults (not the App Group: no widget needs it).
struct WhatsNewStore {
    static let shownVersionKey = "whatsNewShownVersion"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shownVersion: String? {
        defaults.string(forKey: Self.shownVersionKey)
    }

    /// `version` is newer than the one last presented. Without a record
    /// (a build from before this feature) every version is.
    func isNew(_ version: String) -> Bool {
        guard let shownVersion else { return true }
        return WhatsNew.isNewer(version, than: shownVersion)
    }

    /// Whether the popup opens by itself on this launch.
    ///
    /// A launch that opens the welcome flow doesn't open it too: the flow is
    /// the introduction, so the current version is recorded and the popup
    /// stays shut. After that, a version with a list shows it once.
    func showsOnLaunch(version: String, onboardingOpensAtLaunch: Bool) -> Bool {
        guard isNew(version) else { return false }
        if onboardingOpensAtLaunch {
            markShown(version)
            return false
        }
        if WhatsNew.release(for: version) == nil {
            markShown(version)
            return false
        }
        return true
    }

    /// Set when the popup is presented, not when it is closed, so swiping it
    /// away doesn't bring it back. Never moves backwards. Returns whether
    /// this call recorded it, so a repeated `onAppear` is counted once.
    @discardableResult
    func markShown(_ version: String) -> Bool {
        guard isNew(version) else { return false }
        defaults.set(version, forKey: Self.shownVersionKey)
        return true
    }
}
