//
//  SmartStackHints.swift
//  TWAQIWatchWidget
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import AppIntents
import CoreLocation
import WidgetKit

/// Tells the watch Smart Stack when the TWAQI widget is worth bringing up
/// (FOX-75): commute times in Taiwan, near home, and for a while after the
/// followed station crosses the alert threshold. The windows themselves are
/// `SmartStackWindows`.
///
/// Called by the watch app whenever its station, reading or Pro changes, and
/// by the widget on every timeline refresh, so the windows roll forward even
/// when the app isn't opened. Each call replaces the whole set.
enum SmartStackHints {
    /// The configuration donated: the widget's default, AQI with its label.
    private static var intent: SelectIndexIntent {
        SelectIndexIntent(index: .aqi, style: .labelled)
    }

    static func update(isPro: Bool, now: Date = Date()) async {
        // Without Pro the widget only shows a lock: nothing to bring up.
        let intents = isPro ? relevantIntents(now: now) : []
        try? await RelevantIntentManager.shared.updateRelevantIntents(intents)
    }

    private static func relevantIntents(now: Date) -> [RelevantIntent] {
        var contexts = SmartStackWindows.commuteIntervals(from: now).map {
            RelevantContext.date(from: $0.start, to: $0.end)
        }

        // The watch has no copy of the phone's alerts, so it uses the start of
        // Unhealthy for sensitive groups as the threshold.
        if let reading = WatchStore.latestReading,
           let window = SmartStackWindows.alertInterval(
               for: reading, threshold: SmartStackWindows.defaultAlertThreshold, now: now
           ) {
            contexts.append(.date(from: window.start, to: window.end))
        }

        // Only a home found from the reader's location: that means permission
        // was already given. Nothing here ever asks for it.
        if WatchStore.homeIsLocated, let home = WatchStore.homeReading,
           let latitude = home.latitude, let longitude = home.longitude {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                radius: SmartStackWindows.homeRadius,
                identifier: "home-\(home.stationId)"
            )
            contexts.append(.location(region))
        }

        return contexts.map {
            RelevantIntent(intent, widgetKind: SelectIndexIntent.widgetKind, relevance: $0)
        }
    }
}
