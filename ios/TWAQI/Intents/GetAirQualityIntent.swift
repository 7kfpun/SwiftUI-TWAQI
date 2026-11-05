//
//  GetAirQualityIntent.swift
//  TWAQI
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import AppIntents
import SwiftUI

/// "What's the air in Taiwan Air?": the current AQI for a favourite or the
/// nearest station, spoken by Siri and shown in Shortcuts and Spotlight
/// without opening the app (FOX-74). Free, like the widget's small size.
@available(iOS 16.0, *)
struct GetAirQualityIntent: AppIntent {
    static var title: LocalizedStringResource = "Intent.get_air_quality_title"
    static var description = IntentDescription("Intent.get_air_quality_description")

    /// Nil, or "Nearest", is the station nearest the reader.
    @Parameter(title: "Intent.station")
    var station: StationEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get the air at \(\.$station)")
    }

    init() {}

    init(station: StationEntity?) {
        self.station = station
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let result = await AirQualityLookup.lookup(requestedStationId: station?.stationId)
        let text = AirQualityAnswer.text(
            reading: result.reading, freshness: result.freshness, note: result.note,
            locale: .app, bundle: .appLanguage
        )
        TrackingManager.logEvent(.appIntentRun, parameters: [
            "intent": "get_air_quality",
            "station": result.kind,
            "result": result.reading == nil ? "none" : (result.freshness == .live ? "live" : "cached"),
        ])
        return .result(
            dialog: IntentDialog(stringLiteral: text),
            view: AirQualitySnippetView(reading: result.reading)
                .environment(\.locale, .app)
        )
    }
}

/// The card under Siri's answer: the face, the AQI and the level on the
/// level's colour.
struct AirQualitySnippetView: View {
    let reading: WatchReading?

    var body: some View {
        Group {
            if let reading, reading.status(.aqi) != .unknown {
                card(reading)
            } else {
                Text("Intent.answer_no_reading")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    private func card(_ reading: WatchReading) -> some View {
        let status = reading.status(.aqi)
        let foreground = Color(status.getForegroundColor())

        return HStack(spacing: 14) {
            Image(status.getImage())
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: AirQualityAnswer.name(of: reading, locale: .app))
                    .font(.headline)
                    .lineLimit(1)
                Text(status.toString())
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: "AQI")
                    .font(.caption.weight(.semibold))
                    .opacity(0.8)
                Text(verbatim: reading.formatted(.aqi))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundColor(foreground)
        .padding()
        .background(Color(status.getColor()))
    }
}
