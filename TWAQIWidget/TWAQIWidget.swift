//
//  TWAQIWidget.swift
//  TWAQIWidget
//
//  Created by kf on 26/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import AppIntents
import SwiftUI
import WidgetKit

/// Home Screen and Lock Screen widgets for the station the iOS app last
/// resolved (closest / pinned). Shares `WatchStore` keys in the app group so
/// a reading written by the phone is what the extension shows offline.
@main
struct TWAQIWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TWAQIWidget", intent: SelectIndexIntent.self, provider: ReadingProvider()) { entry in
            ReadingWidgetView(entry: entry)
                .widgetContainerBackground(tint: entry.tintColor)
        }
        .configurationDisplayName("Widget.widget_name")
        .description("Widget.widget_description")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

/// Which index a widget shows. Mirrors `AirIndexTypes`, which can't conform to
/// `AppEnum` itself without dragging AppIntents into every target that uses it.
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

    // Required by AppIntent on the current SDK when building an app extension;
    // configuration intents never run this path for widgets.
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct ReadingEntry: TimelineEntry {
    let date: Date
    let reading: WatchReading?
    let airIndexType: AirIndexTypes

    var tintColor: Color {
        guard let reading else { return Color(0x676767) }
        return Color(reading.status(airIndexType).getColor())
    }
}

struct ReadingProvider: AppIntentTimelineProvider {
    /// Readings are published hourly; half that keeps a widget at most one
    /// publish behind without spending the refresh budget.
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
        // the widget.
        if let pollutant {
            reading = WatchReading(pollutant)
            WatchStore.latestReading = reading
        }

        let entry = ReadingEntry(
            date: Date(), reading: reading, airIndexType: configuration.index.airIndexType
        )
        return Timeline(entries: [entry], policy: .after(next))
    }
}

struct ReadingWidgetView: View {
    let entry: ReadingEntry

    @Environment(\.widgetFamily) private var family

    private var type: AirIndexTypes { entry.airIndexType }

    var body: some View {
        if let reading = entry.reading {
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
        case .systemSmall:
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: type.toString())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: value)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Color(status.getForegroundColor()))
                Spacer(minLength: 0)
                Text(reading.displayName)
                    .font(.caption2)
                    .foregroundStyle(Color(status.getForegroundColor()).opacity(0.85))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(12)
            .background(tint)

        case .systemMedium, .systemLarge:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(reading.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(status.toString())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if family == .systemLarge {
                        Text(verbatim: "\(type.toString()) \(value) \(type.getUnit())".trimmingCharacters(in: .whitespaces))
                            .font(.title2.monospacedDigit().weight(.semibold))
                        Spacer(minLength: 0)
                        if !reading.publishTime.isEmpty {
                            Text(verbatim: reading.publishTime)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(verbatim: "\(type.toString()) \(value)")
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.2))
                    if status.hasFaceImage {
                        Image(status.getImage())
                            .resizable()
                            .scaledToFit()
                            .padding(family == .systemLarge ? 18 : 12)
                    } else {
                        Text(verbatim: value)
                            .font(.title.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: family == .systemLarge ? 96 : 64, height: family == .systemLarge ? 96 : 64)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(16)

        case .accessoryCircular:
            Gauge(value: bandProgress(status), in: 0...1) {
                Text(verbatim: type.toString())
            } currentValueLabel: {
                Text(value)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(tint)

        case .accessoryRectangular:
            HStack(spacing: 6) {
                if status.hasFaceImage {
                    Image(status.getImage())
                        .resizable()
                        .frame(width: 18, height: 18)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(status.toString())
                        .font(.headline)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(verbatim: "\(type.toString()) \(value)")
                        .monospacedDigit()
                    Text(reading.displayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            // accessoryInline and any future family.
            Text(verbatim: "\(reading.displayName) · \(type.toString()) \(value)")
        }
    }

    private func bandProgress(_ status: AirStatuses) -> Double {
        let bands = AirStatuses.getShowAllCases()
        let band = bands.firstIndex(of: status).map { $0 + 1 } ?? 0
        return Double(band) / Double(bands.count)
    }

    private var empty: some View {
        Group {
            switch family {
            case .systemSmall, .systemMedium, .systemLarge:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Widget.widget_name")
                        .font(.headline)
                    Text("Watch.no_station")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(12)
            case .accessoryRectangular:
                Text("Watch.no_station")
                    .font(.footnote)
            default:
                Text(verbatim: "\(type.toString()) --")
            }
        }
    }
}

private extension View {
    /// iOS 17+ container background; older Home Screen widgets keep a clear fill.
    @ViewBuilder
    func widgetContainerBackground(tint: Color) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                tint.opacity(0.15)
            }
        } else {
            self
        }
    }
}
