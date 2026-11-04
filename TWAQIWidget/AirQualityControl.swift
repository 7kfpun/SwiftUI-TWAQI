//
//  AirQualityControl.swift
//  TWAQIWidget
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import AppIntents
import CoreLocation
import SwiftUI
import WidgetKit

@main
struct TWAQIWidgetBundle: WidgetBundle {
    var body: some Widget {
        TWAQIWidget()
        if #available(iOS 18.0, *) {
            AirQualityControl()
        }
    }
}

/// Control Center, Lock Screen and Action button control (FOX-74): the AQI
/// of a favourite or the nearest station; a tap opens that station in the
/// app. Free. Reads the widget's app group data and fetch.
///
/// Controls draw only symbols, not the app's face images, so the level
/// shows as an `aqi.*` symbol in the level's colour, and in words.
@available(iOS 18.0, *)
struct AirQualityControl: ControlWidget {
    static let kind = "TWAQIAirQualityControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: AirQualityControlProvider()) { value in
            ControlWidgetButton(action: OpenStationControlIntent(stationId: value.stationId)) {
                Label {
                    Text(verbatim: value.title)
                    Text(verbatim: value.subtitle)
                } icon: {
                    Image(systemName: value.symbolName)
                }
            }
            .tint(value.tint)
        }
        .displayName("Control.display_name")
        .description("Control.description")
    }
}

/// Which station the control shows: "Nearest" (or none) is the station the
/// app last showed for the reader's location, like the widget's "closest".
@available(iOS 18.0, *)
struct AirQualityControlConfiguration: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Control.configuration_title"

    @Parameter(title: "Intent.station")
    var station: StationEntity?

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// What the control draws. Strings are built in the app's language, as the
/// widget's are.
struct AirQualityControlValue {
    let stationId: Int?
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color

    init(reading: WatchReading?, bundle: Bundle = .appLanguage, locale: Locale = .app) {
        stationId = reading?.stationId
        guard let reading, reading.status(.aqi) != .unknown else {
            title = "AQI –"
            subtitle = reading.map { AirQualityAnswer.name(of: $0, locale: locale) }
                ?? bundle.localizedString(forKey: "Watch.no_station", value: nil, table: nil)
            symbolName = "aqi.low"
            tint = Color(0x676767)
            return
        }
        let status = reading.status(.aqi)
        title = "AQI \(reading.formatted(.aqi))"
        subtitle = "\(AirQualityAnswer.name(of: reading, locale: locale)) · "
            + bundle.localizedString(forKey: "AirStatus.\(status.rawValue)", value: nil, table: nil)
        symbolName = Self.symbolName(for: status)
        tint = Color(status.getColor())
    }

    static func symbolName(for status: AirStatuses) -> String {
        switch status {
        case .good, .moderate, .unknown: return "aqi.low"
        case .unhealthyforsensitivegroup, .unhealthy: return "aqi.medium"
        case .veryunhealthy, .hazardous: return "aqi.high"
        }
    }
}

@available(iOS 18.0, *)
struct AirQualityControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: AirQualityControlConfiguration) -> AirQualityControlValue {
        AirQualityControlValue(reading: .placeholder)
    }

    func currentValue(configuration: AirQualityControlConfiguration) async throws -> AirQualityControlValue {
        // The widget's "closest": the extension can't locate the reader, so
        // it follows the station the app last showed.
        let appClosest = WatchStore.pinnedStationId ?? WatchStore.latestReading?.stationId
        let resolution = StationResolution.resolve(
            requestedStationId: configuration.station?.stationId,
            favouriteIds: WatchStore.favouriteStationIds,
            locationAvailable: Self.locationAllowed && appClosest != nil
        )

        let stationId: Int?
        switch resolution.plan {
        case .station(let id): stationId = id
        case .nearest, .defaultLocation: stationId = appClosest
        }

        guard let stationId else {
            // Before the app has ever run: the 中正 default, as the widget.
            let all = (try? await WatchAPI.currentPollutants()) ?? []
            return AirQualityControlValue(
                reading: WatchAPI.closest(to: WatchAPI.defaultLocation, in: all).map(WatchReading.init)
            )
        }
        if let pollutant = try? await WatchAPI.currentPollutant(stationId: stationId) {
            let reading = WatchReading(pollutant)
            if WatchStore.favouriteStationIds.contains(stationId) {
                WatchStore.cacheFavouriteReadings([reading])
            }
            return AirQualityControlValue(reading: reading)
        }
        return AirQualityControlValue(reading: WatchStore.newestCachedReading(stationId: stationId))
    }

    /// An extension shares its app's location permission; this never asks.
    private static var locationAllowed: Bool {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }
}

/// The control's tap: opens the app on the station (`twaqi://station`), or
/// just opens the app when there is no station yet.
@available(iOS 18.0, *)
struct OpenStationControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Intent.open_station_title"
    static var isDiscoverable = false

    @Parameter(title: "Intent.station")
    var stationId: Int?

    init() {}

    init(stationId: Int?) {
        self.stationId = stationId
    }

    enum Failure: Error {
        case noURL
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = stationId.flatMap({ DeepLink.stationURL(stationId: $0, source: .control) })
            ?? URL(string: "\(DeepLink.scheme)://")
        else { throw Failure.noURL }
        return .result(opensIntent: OpenURLIntent(url))
    }
}
