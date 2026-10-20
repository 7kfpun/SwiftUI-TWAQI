//
//  TWAQIWatchWidget.swift
//  TWAQIWatchWidget
//
//  Created by kf on 20/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import AppIntents
import SwiftUI
import WidgetKit

/// Watch-face complications for the station chosen in the watch app.
///
/// Replaces the old ClockKit data source; WidgetKit accessory families cover
/// the circular, corner, rectangular and inline slots on current faces.
@main
struct TWAQIWatchWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TWAQIWatchWidget", intent: SelectIndexIntent.self, provider: ReadingProvider()) { entry in
            ReadingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Watch.widget_name")
        .description("Watch.widget_description")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

/// Which index a complication shows. Mirrors `AirIndexTypes`, which can't
/// conform to `AppEnum` itself without dragging AppIntents into the iOS app.
enum IndexOption: String, AppEnum {
    case aqi, pm25, pm10, o3, co, so2, no2

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Index"

    static var caseDisplayRepresentations: [IndexOption: DisplayRepresentation] = [
        .aqi: "AQI",
        .pm25: "PM2.5",
        .pm10: "PM10",
        .o3: "O3",
        .co: "CO",
        .so2: "SO2",
        .no2: "NO2",
    ]

    var airIndexType: AirIndexTypes {
        AirIndexTypes(rawValue: rawValue) ?? .aqi
    }
}

struct SelectIndexIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Index"

    @Parameter(title: "Index", default: .aqi)
    var index: IndexOption

    init() {}

    init(index: IndexOption) {
        self.index = index
    }
}

struct ReadingEntry: TimelineEntry {
    let date: Date
    let reading: WatchReading?
    let airIndexType: AirIndexTypes
    /// Without the upgrade the complication shows a lock, not the reading.
    var isLocked = false
}

struct ReadingProvider: AppIntentTimelineProvider {
    /// Readings are published hourly; half that keeps a complication at most
    /// one publish behind without spending the refresh budget.
    private static let refreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> ReadingEntry {
        ReadingEntry(date: Date(), reading: .placeholder, airIndexType: .aqi)
    }

    func snapshot(for configuration: SelectIndexIntent, in context: Context) async -> ReadingEntry {
        ReadingEntry(
            date: Date(),
            reading: WatchStore.latestReading ?? .placeholder,
            airIndexType: configuration.index.airIndexType
        )
    }

    func timeline(for configuration: SelectIndexIntent, in context: Context) async -> Timeline<ReadingEntry> {
        let next = Date().addingTimeInterval(Self.refreshInterval)
        guard await WatchPro.refresh() else {
            // The app reloads every timeline the moment a purchase lands.
            let entry = ReadingEntry(
                date: Date(), reading: nil, airIndexType: configuration.index.airIndexType, isLocked: true
            )
            return Timeline(entries: [entry], policy: .after(next))
        }

        var reading = WatchStore.latestReading
        // The app resolves home from the reader's location; the extension
        // can't, so it follows whichever station the app last showed. Before
        // the app has ever run, that is the 中正 default.
        let pollutant: Pollutant?
        if let stationId = WatchStore.pinnedStationId ?? reading?.stationId {
            pollutant = try? await WatchAPI.currentPollutant(stationId: stationId)
        } else {
            let stations = (try? await WatchAPI.currentPollutants()) ?? []
            pollutant = WatchAPI.closest(to: WatchAPI.defaultLocation, in: stations)
        }
        // Falls back to the cached reading when offline rather than blanking
        // the complication.
        if let pollutant {
            reading = WatchReading(pollutant)
            WatchStore.latestReading = reading
        }

        let entry = ReadingEntry(date: Date(), reading: reading, airIndexType: configuration.index.airIndexType)
        return Timeline(entries: [entry], policy: .after(next))
    }

    /// watchOS has no editor for intent parameters on the face, so each index
    /// is offered as its own complication in the picker.
    func recommendations() -> [AppIntentRecommendation<SelectIndexIntent>] {
        IndexOption.allCases.map { option in
            AppIntentRecommendation(
                intent: SelectIndexIntent(index: option),
                description: Text(verbatim: option.airIndexType.toString())
            )
        }
    }
}

struct ReadingWidgetView: View {
    let entry: ReadingEntry

    @Environment(\.widgetFamily) private var family

    private var type: AirIndexTypes { entry.airIndexType }

    var body: some View {
        if entry.isLocked {
            locked
        } else if let reading = entry.reading {
            content(reading)
        } else {
            empty
        }
    }

    @ViewBuilder
    private func content(_ reading: WatchReading) -> some View {
        let status = reading.status(type)
        let tint = Color(status.getColor())
        let value = reading.formatted(type)

        switch family {
        case .accessoryCircular:
            gauge(status, value: value, tint: tint)
                .gaugeStyle(.accessoryCircular)

        case .accessoryCorner:
            Text(value)
                .font(.title3)
                .widgetCurvesContent()
                .widgetLabel {
                    gauge(status, value: value, tint: tint)
                }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(status.toString())
                    .font(.headline)
                    .foregroundStyle(tint)
                    .widgetAccentable()

                Text(verbatim: "\(type.toString()) \(value) \(type.getUnit())")
                    .monospacedDigit()

                Text(reading.displayName)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            Text(verbatim: "\(type.toString()) \(value) · \(reading.displayName)")
        }
    }

    /// Fills by health band rather than raw value. Each index has its own units
    /// and breakpoints, so a band is the one scale that reads the same for AQI
    /// and for CO in ppm.
    private func gauge(_ status: AirStatuses, value: String, tint: Color) -> some View {
        let bands = AirStatuses.getShowAllCases()
        let band = bands.firstIndex(of: status).map { $0 + 1 } ?? 0

        return Gauge(value: Double(band), in: 0...Double(bands.count)) {
            Text(verbatim: type.toString())
        } currentValueLabel: {
            Text(value)
        }
        .tint(tint)
    }

    /// Points the reader at the app, where the paywall is.
    private var locked: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                Label("Watch.pro_locked", systemImage: "lock.fill")
                    .font(.footnote)
            case .accessoryInline:
                Label("Watch.pro_locked", systemImage: "lock.fill")
            default:
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .widgetAccentable()
            }
        }
    }

    /// No station chosen yet — the app's first launch sets one.
    private var empty: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                Text("Watch.no_station")
                    .font(.footnote)
            default:
                Text(verbatim: "\(type.toString()) --")
            }
        }
    }
}
