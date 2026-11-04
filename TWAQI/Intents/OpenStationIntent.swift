//
//  OpenStationIntent.swift
//  TWAQI
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import AppIntents
import Foundation

/// Opens the app on a station's page, for a Shortcut or the Action button
/// that should show the whole page rather than say the AQI (FOX-74).
@available(iOS 16.0, *)
struct OpenStationIntent: AppIntent {
    static var title: LocalizedStringResource = "Intent.open_station_title"
    static var description = IntentDescription("Intent.open_station_description")
    static var openAppWhenRun = true

    @Parameter(title: "Intent.station")
    var station: StationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$station)")
    }

    init() {}

    init(station: StationEntity) {
        self.station = station
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // "Nearest" is opened as whichever station answers for it, the same
        // one Siri would read out.
        let stationId: Int?
        let kind: String
        if let id = station.stationId {
            stationId = id
            kind = "station"
        } else {
            let result = await AirQualityLookup.lookup(requestedStationId: nil)
            stationId = result.reading?.stationId
            kind = result.kind
        }
        TrackingManager.logEvent(.appIntentRun, parameters: [
            "intent": "open_station",
            "station": kind,
            "result": stationId == nil ? "none" : "opened",
        ])
        if let stationId, let url = DeepLink.stationURL(stationId: stationId, source: .shortcut) {
            PendingLink.post(url)
        }
        return .result()
    }
}

/// A link the app was asked to open from inside its own process (an App
/// Intent run with `openAppWhenRun`), which no `openURLContexts` delivers.
/// `SceneDelegate` opens it at once if a scene is active, else on activation.
enum PendingLink {
    static let didPost = Notification.Name("TWAQI.PendingLink.didPost")

    @MainActor private static var url: URL?

    @MainActor
    static func post(_ url: URL) {
        self.url = url
        NotificationCenter.default.post(name: didPost, object: nil)
    }

    /// The waiting link, once.
    @MainActor
    static func take() -> URL? {
        defer { url = nil }
        return url
    }
}
