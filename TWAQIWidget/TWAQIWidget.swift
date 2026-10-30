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
///
/// Small and medium also list the reader's other favourite stations; large
/// does with Pro. The Lock Screen families stay single-station.
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
    /// Whether this family lists favourites (see `ReadingProvider.listsFavourites`).
    var listsFavourites = false
    /// Saved favourites other than `reading`, in the reader's order.
    var favourites: [WatchReading] = []

    var tintColor: Color {
        guard let reading else { return Color(0x676767) }
        return Color(reading.status(airIndexType).getColor())
    }
}

struct ReadingProvider: AppIntentTimelineProvider {
    /// Readings are published hourly; half that keeps a widget at most one
    /// publish behind without spending the refresh budget.
    private static let refreshInterval: TimeInterval = 30 * 60

    /// Small and medium list favourites for everyone, large only with Pro.
    static func listsFavourites(in family: WidgetFamily) -> Bool {
        switch family {
        case .systemSmall, .systemMedium: return true
        case .systemLarge: return WatchStore.isProUnlocked
        default: return false
        }
    }

    /// Favourites in the reader's order, minus the primary station, from the
    /// cache. A station never fetched yet is left out rather than shown blank.
    private static func cachedFavourites(excluding primaryId: Int?) -> [WatchReading] {
        let cached = Dictionary(
            WatchStore.favouriteReadings.map { ($0.stationId, $0) }, uniquingKeysWith: { _, latest in latest }
        )
        var seen: Set<Int> = []
        return WatchStore.favouriteStationIds.compactMap { id in
            guard id != primaryId, seen.insert(id).inserted else { return nil }
            return cached[id]
        }
    }

    func placeholder(in context: Context) -> ReadingEntry {
        let lists = Self.listsFavourites(in: context.family)
        return ReadingEntry(
            date: Date(), reading: .placeholder, airIndexType: .aqi,
            listsFavourites: lists, favourites: lists ? WatchReading.placeholderFavourites : []
        )
    }

    func snapshot(for configuration: SelectIndexIntent, in context: Context) async -> ReadingEntry {
        let reading = WatchStore.latestReading ?? .placeholder
        let lists = Self.listsFavourites(in: context.family)
        var favourites: [WatchReading] = []
        if lists {
            favourites = Self.cachedFavourites(excluding: reading.stationId)
            // The gallery shows what the size can do, even before any favourite.
            if favourites.isEmpty, context.isPreview {
                favourites = WatchReading.placeholderFavourites
            }
        }
        return ReadingEntry(
            date: Date(), reading: reading, airIndexType: configuration.index.airIndexType,
            listsFavourites: lists, favourites: favourites
        )
    }

    func timeline(for configuration: SelectIndexIntent, in context: Context) async -> Timeline<ReadingEntry> {
        let next = Date().addingTimeInterval(Self.refreshInterval)
        var reading = WatchStore.latestReading
        let lists = Self.listsFavourites(in: context.family)
        let favouriteIds = lists ? WatchStore.favouriteStationIds : []

        // The app resolves home from the reader's location; the extension
        // can't, so it follows whichever station the app last showed. Before
        // the app has ever run, that is the 中正 default.
        let pollutant: Pollutant?
        var fetched: Pollutants = []
        if let stationId = WatchStore.pinnedStationId ?? reading?.stationId {
            if favouriteIds.isEmpty {
                pollutant = try? await WatchAPI.currentPollutant(stationId: stationId)
            } else {
                // One request for the primary station and the favourites.
                fetched = (try? await WatchAPI.currentPollutants(stationIds: [stationId] + favouriteIds)) ?? []
                pollutant = fetched.first { $0.stationId == stationId }
            }
        } else {
            // Every station, so favourites come along for free.
            fetched = (try? await WatchAPI.currentPollutants()) ?? []
            pollutant = WatchAPI.closest(to: WatchAPI.defaultLocation, in: fetched)
        }
        // Falls back to the cached reading when offline rather than blanking
        // the widget.
        if let pollutant {
            reading = WatchReading(pollutant)
            WatchStore.latestReading = reading
        }

        var favourites: [WatchReading] = []
        if !favouriteIds.isEmpty {
            let ids = Set(favouriteIds)
            WatchStore.cacheFavouriteReadings(fetched.filter { ids.contains($0.stationId) }.map(WatchReading.init))
            favourites = Self.cachedFavourites(excluding: reading?.stationId)
        }

        let entry = ReadingEntry(
            date: Date(), reading: reading, airIndexType: configuration.index.airIndexType,
            listsFavourites: lists, favourites: favourites
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
        case .systemSmall where !entry.favourites.isEmpty:
            smallWithFavourites(reading)

        case .systemMedium where !entry.favourites.isEmpty:
            mediumWithFavourites(reading)

        // With Pro and nothing saved, large says how to add favourites rather
        // than falling back to the plain layout.
        case .systemLarge where entry.listsFavourites:
            largeWithFavourites(reading)

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

    // MARK: - Favourites

    private func smallWithFavourites(_ reading: WatchReading) -> some View {
        let status = reading.status(type)
        let foreground = Color(status.getForegroundColor())

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(reading.displayName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: reading.formatted(type))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(foreground)
                Spacer(minLength: 0)
                if status.hasFaceImage {
                    Image(status.getImage())
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(status.getColor()), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            favouriteRows(limit: 2, showsStatus: false)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func mediumWithFavourites(_ reading: WatchReading) -> some View {
        let status = reading.status(type)
        let tint = Color(status.getColor())

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(reading.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(status.toString())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 6) {
                    Text(verbatim: "\(type.toString()) \(reading.formatted(type))")
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    face(status, value: reading.formatted(type), size: 40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                favouriteRows(limit: 3, showsStatus: false)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(4)
    }

    private func largeWithFavourites(_ reading: WatchReading) -> some View {
        let status = reading.status(type)
        let tint = Color(status.getColor())
        let value = reading.formatted(type)

        return VStack(alignment: .leading, spacing: 8) {
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
                    Text(verbatim: "\(type.toString()) \(value) \(type.getUnit())".trimmingCharacters(in: .whitespaces))
                        .font(.title2.monospacedDigit().weight(.semibold))
                }
                Spacer(minLength: 0)
                face(status, value: value, size: 72)
            }

            Divider()

            Text("Widget.favourites")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if entry.favourites.isEmpty {
                Text("Widget.no_favourites")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                favouriteRows(limit: 5, showsStatus: true)
            }

            Spacer(minLength: 0)
            if !reading.publishTime.isEmpty {
                Text(verbatim: reading.publishTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(4)
    }

    private func favouriteRows(limit: Int, showsStatus: Bool) -> some View {
        ForEach(Array(entry.favourites.prefix(limit)), id: \.stationId) { reading in
            favouriteRow(reading, showsStatus: showsStatus)
        }
    }

    private func favouriteRow(_ reading: WatchReading, showsStatus: Bool) -> some View {
        let status = reading.status(type)
        let tint = Color(status.getColor())

        return HStack(spacing: 6) {
            Text(reading.displayName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            if showsStatus {
                Text(status.toString())
                    .font(.caption2)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            Text(verbatim: reading.formatted(type))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color(status.getForegroundColor()))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(minWidth: 36)
                .background(tint, in: Capsule())
        }
    }

    /// The status face in a tinted circle, or the value where a band has no face.
    private func face(_ status: AirStatuses, value: String, size: CGFloat) -> some View {
        let tint = Color(status.getColor())

        return ZStack {
            Circle()
                .fill(tint.opacity(0.2))
            if status.hasFaceImage {
                Image(status.getImage())
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
            } else {
                Text(verbatim: value)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
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

#if DEBUG
private extension ReadingEntry {
    static func preview(listsFavourites: Bool = true, favourites: [WatchReading] = WatchReading.placeholderFavourites) -> ReadingEntry {
        ReadingEntry(
            date: Date(), reading: .placeholder, airIndexType: .aqi,
            listsFavourites: listsFavourites, favourites: favourites
        )
    }
}

#Preview("Small", as: .systemSmall) {
    TWAQIWidget()
} timeline: {
    ReadingEntry.preview()
    ReadingEntry.preview(favourites: [])
}

#Preview("Medium", as: .systemMedium) {
    TWAQIWidget()
} timeline: {
    ReadingEntry.preview()
    ReadingEntry.preview(favourites: [])
}

#Preview("Large · Pro", as: .systemLarge) {
    TWAQIWidget()
} timeline: {
    ReadingEntry.preview()
    ReadingEntry.preview(favourites: [])
}

#Preview("Large · no Pro", as: .systemLarge) {
    TWAQIWidget()
} timeline: {
    ReadingEntry.preview(listsFavourites: false, favourites: [])
}
#endif
