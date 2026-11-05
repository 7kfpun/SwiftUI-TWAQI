//
//  TWAQIShortcuts.swift
//  TWAQI
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import AppIntents

/// The App Shortcuts: listed in Spotlight and the Shortcuts app with no setup,
/// spoken to Siri, and available to the Action button (Settings → Action
/// Button → Shortcut). Chinese phrases are in `AppShortcuts.strings` (FOX-74).
@available(iOS 16.0, *)
struct TWAQIShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetAirQualityIntent(),
            phrases: [
                "What's the air in \(.applicationName)",
                "\(.applicationName) air quality",
                "\(.applicationName) air at \(\.$station)",
                "What's the air at \(\.$station) in \(.applicationName)",
            ],
            shortTitle: "Intent.get_air_quality_short",
            systemImageName: "aqi.medium"
        )
        AppShortcut(
            intent: OpenStationIntent(),
            phrases: [
                "Open \(\.$station) in \(.applicationName)",
                "Open a station in \(.applicationName)",
            ],
            shortTitle: "Intent.open_station_short",
            systemImageName: "location.circle"
        )
    }

    /// Station phrases ("Taiwan Air air at Songshan") list the favourites;
    /// call when they change so Siri learns the new names.
    static func favouritesChanged() {
        updateAppShortcutParameters()
    }
}
