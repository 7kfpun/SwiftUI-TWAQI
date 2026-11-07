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
/// resolved (closest / pinned), or the reader's first favourite. Shares
/// `WatchStore` keys in the app group so a reading written by the phone is
/// what the extension shows offline.
///
/// Small, medium and large also list the reader's other favourite stations.
/// Extra large (iPad) shows the one station in detail instead: history,
/// forecast and cam (FOX-72). Medium, large and extra large are Pro; without
/// it they say so instead. With Pro, medium and large page through the favourites with ‹ ›, and every Home Screen size cycles
/// its index when the label is tapped (FOX-76, `WidgetPaging`). The Lock
/// Screen families stay single-station. Bundled with the Control Center control
/// (`TWAQIWidgetBundle`).
struct TWAQIWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TWAQIWidget", intent: SelectIndexIntent.self, provider: ReadingProvider()) { entry in
            ReadingWidgetView(entry: entry)
                .appLanguageLocale()
                .widgetContainerBackground(tint: entry.tintColor)
        }
        .configurationDisplayName("Widget.widget_name")
        .description("Widget.widget_description")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge,
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

/// Which station a widget leads with. The rest of the favourites are listed
/// under it either way.
enum StationOption: String, AppEnum {
    case closest, firstFavourite, station

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Widget.station"

    static var caseDisplayRepresentations: [StationOption: DisplayRepresentation] = [
        .closest: "Widget.station_closest",
        .firstFavourite: "Widget.station_first_favourite",
        .station: "Widget.station_chosen",
    ]

    var mode: WidgetStationMode {
        switch self {
        case .closest: return .closest
        case .firstFavourite: return .firstFavourite
        case .station: return .station
        }
    }
}

struct SelectIndexIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Index"

    @Parameter(title: "Widget.station", default: .closest)
    var station: StationOption

    /// Any of the country's stations, searchable. Read only when `station`
    /// is "Station" (FOX-137).
    @Parameter(title: "Widget.station_picker")
    var chosenStation: ChosenStationEntity?

    @Parameter(title: "Index", default: .aqi)
    var index: IndexOption

    static var parameterSummary: some ParameterSummary {
        When(\.$station, .equalTo, StationOption.station) {
            Summary("\(\.$station) \(\.$chosenStation) \(\.$index)")
        } otherwise: {
            Summary("\(\.$station) \(\.$index)")
        }
    }

    init() {}

    init(station: StationOption = .closest, chosenStation: ChosenStationEntity? = nil, index: IndexOption) {
        self.station = station
        self.chosenStation = chosenStation
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
    /// The station shown: the widget's own, or the favourite paged to.
    var reading: WatchReading?
    var airIndexType: AirIndexTypes
    /// Whether this family lists favourites (see `ReadingProvider.listsFavourites`).
    var listsFavourites = false
    /// Saved favourites other than `reading`, in the reader's order.
    var favourites: [WatchReading] = []
    /// A Pro family placed without Pro: stations are shown, their numbers
    /// blurred under a line selling Pro.
    var isLocked = false
    /// Extra large only: the station's history, forecast and cam, each
    /// possibly missing.
    var detail: WidgetStationDetail?
    /// Extra large only: the cam's latest frame, downsampled.
    var camFrame: UIImage?
    /// How far up a StandBy or Home Screen Smart Rotate stack this entry
    /// should go (`WidgetRelevance`).
    var relevance: TimelineEntryRelevance?
    /// This widget's key for its page state (`WidgetPaging.key`). Nil where
    /// there are no buttons: Lock Screen families and placeholders.
    var widgetKey: String?
    /// The stations ‹ › page through, the widget's own first
    /// (`WidgetPaging.pageIds`), and which of them is shown.
    var pageIds: [Int] = []
    var page = 0
    /// Medium and large with Pro and at least two favourites (FOX-76).
    var showsPager = false

    var tintColor: Color {
        guard let reading, !isLocked else { return Color(0x676767) }
        return Color(reading.status(airIndexType).getColor())
    }

    /// The index label cycles on tap, except on a locked widget.
    var cyclesIndex: Bool { widgetKey != nil && !isLocked }
}

struct ReadingProvider: AppIntentTimelineProvider {
    /// Readings are published hourly; half that keeps a widget at most one
    /// publish behind without spending the refresh budget.
    private static let refreshInterval: TimeInterval = 30 * 60

    /// Home Screen families list favourites; Lock Screen ones have no room.
    static func listsFavourites(in family: WidgetFamily) -> Bool {
        WidgetFamilyRules.listsFavourites(family)
    }

    /// Medium and large page through favourites with ‹ › (FOX-76).
    static func pagesFavourites(in family: WidgetFamily) -> Bool {
        family == .systemMedium || family == .systemLarge
    }

    /// Medium and large are Pro. The gallery still previews them unlocked.
    static func isLocked(in context: Context) -> Bool {
        WidgetFamilyRules.isLocked(context.family, isPro: WatchStore.isProUnlocked, isPreview: context.isPreview)
    }

    /// The key a Home Screen widget keeps its page and index under. Nil for
    /// Lock Screen families, which have no buttons.
    static func widgetKey(family: WidgetFamily, configuration: SelectIndexIntent) -> String? {
        let name: String
        switch family {
        case .systemSmall: name = "small"
        case .systemMedium: name = "medium"
        case .systemLarge: name = "large"
        default: return nil
        }
        let station = WidgetStationChoice.keyPart(mode: configuration.station.mode, chosenId: configuration.chosenStation?.stationId)
        return WidgetPaging.key(family: name, station: station, index: configuration.index.rawValue)
    }

    /// The station a widget leads with, when it's set to a favourite or a
    /// chosen station. `nil` means the closest station, also the fallback
    /// while no favourite is saved or no station is picked.
    private static func leadingStationId(for configuration: SelectIndexIntent) -> Int? {
        WidgetStationChoice.leadingId(
            mode: configuration.station.mode,
            chosenId: configuration.chosenStation?.stationId,
            firstFavouriteId: WatchStore.favouriteStationIds.first
        )
    }

    private static func cachedFavourite(_ stationId: Int) -> WatchReading? {
        WatchStore.cachedReading(stationId: stationId)
    }

    /// The widget's own station from saved readings only, as the last
    /// timeline left it.
    private static func cachedLeadingReading(for configuration: SelectIndexIntent) -> WatchReading? {
        leadingStationId(for: configuration).flatMap(cachedFavourite) ?? WatchStore.latestReading
    }

    /// What the widget draws, from saved readings: the page `state` points
    /// at (the widget's own station, `leading`, by default), the other
    /// favourites under it, and the index the label was cycled to. A
    /// favourite never fetched yet is left out rather than shown blank.
    static func makeEntry(
        date: Date, leading: WatchReading?, configuration: SelectIndexIntent, family: WidgetFamily,
        isPreview: Bool, isLocked: Bool, state: WidgetPageState, relevance: TimelineEntryRelevance? = nil
    ) -> ReadingEntry {
        let configuredIndex = configuration.index.airIndexType
        let key = widgetKey(family: family, configuration: configuration)
        var entry = ReadingEntry(date: date, reading: leading, airIndexType: configuredIndex, relevance: relevance)
        guard listsFavourites(in: family) else {
            // Extra large is Pro and shows one station in detail (FOX-72).
            if WidgetFamilyRules.showsStationDetail(family) {
                entry.isLocked = isLocked
            }
            return entry
        }

        entry.listsFavourites = true
        entry.isLocked = isLocked
        entry.widgetKey = key
        if entry.cyclesIndex {
            entry.airIndexType = WidgetPaging.index(state, configured: configuredIndex)
        }

        let favouriteIds = WatchStore.favouriteStationIds
        var readings = Dictionary(
            WatchStore.favouriteReadings.map { ($0.stationId, $0) }, uniquingKeysWith: { _, latest in latest }
        )
        let saved = favouriteIds.filter { readings[$0] != nil }
        if let leading {
            readings[leading.stationId] = leading
        }
        let pageIds = WidgetPaging.pageIds(defaultId: leading?.stationId, favouriteIds: saved)
        entry.pageIds = pageIds
        entry.showsPager = pagesFavourites(in: family) && entry.cyclesIndex && leading != nil
            && WidgetPaging.showsPager(favouriteCount: favouriteIds.count, pageCount: pageIds.count)
        if entry.showsPager {
            entry.page = WidgetPaging.currentPage(state, pageIds: pageIds, now: date)
            entry.reading = readings[pageIds[entry.page]] ?? leading
        }

        // The station shown is never listed again under itself.
        var seen: Set<Int> = []
        entry.favourites = saved.compactMap { id in
            guard id != entry.reading?.stationId, seen.insert(id).inserted else { return nil }
            return readings[id]
        }
        // The gallery shows what the size can do, even before any favourite.
        if entry.favourites.isEmpty, isPreview {
            entry.favourites = WatchReading.placeholderFavourites
        }
        return entry
    }

    func placeholder(in context: Context) -> ReadingEntry {
        let lists = Self.listsFavourites(in: context.family)
        return ReadingEntry(
            date: Date(), reading: .placeholder, airIndexType: .aqi,
            listsFavourites: lists, favourites: lists ? WatchReading.placeholderFavourites : [],
            detail: WidgetFamilyRules.showsStationDetail(context.family) ? .placeholder : nil
        )
    }

    func snapshot(for configuration: SelectIndexIntent, in context: Context) async -> ReadingEntry {
        let state = Self.widgetKey(family: context.family, configuration: configuration)
            .map { WidgetPageStore.state(for: $0, in: WatchStore.sharedDefaults) } ?? WidgetPageState()
        let leading = Self.cachedLeadingReading(for: configuration) ?? .placeholder
        var entry = Self.makeEntry(
            date: Date(), leading: leading,
            configuration: configuration, family: context.family, isPreview: context.isPreview,
            isLocked: Self.isLocked(in: context), state: state
        )
        if WidgetFamilyRules.showsStationDetail(context.family) {
            (entry.detail, entry.camFrame) = StationDetailLoader.cached(stationId: leading.stationId)
            // The gallery shows what the size can do, before any fetch.
            if entry.detail == nil, context.isPreview {
                entry.detail = .placeholder
            }
        }
        return entry
    }

    func timeline(for configuration: SelectIndexIntent, in context: Context) async -> Timeline<ReadingEntry> {
        let now = Date()
        let next = now.addingTimeInterval(Self.refreshInterval)
        let isLocked = Self.isLocked(in: context)
        let key = Self.widgetKey(family: context.family, configuration: configuration)
        let defaults = WatchStore.sharedDefaults
        var state = key.map { WidgetPageStore.state(for: $0, in: defaults) } ?? WidgetPageState()

        // A ‹ › or index tap: redraw from saved readings at once, no network.
        if key != nil, WidgetPaging.isTapReload(state, now: now) {
            return Self.tapTimeline(
                configuration: configuration, context: context, isLocked: isLocked, state: state, now: now
            )
        }

        var reading = WatchStore.latestReading
        let lists = Self.listsFavourites(in: context.family)
        let favouriteIds = lists ? WatchStore.favouriteStationIds : []

        var fetched: Pollutants = []
        var hasNewData = false
        /// The leading station as this refresh fetched it, for extra large.
        var primary: Pollutant?
        var leadingId = Self.leadingStationId(for: configuration)
        if let id = leadingId {
            // One request covers the leading station and the favourites. Its
            // reading goes to the favourite cache (or the chosen-station
            // cache): `latestReading` tracks the closest station.
            let ids = favouriteIds.contains(id) ? favouriteIds : [id] + favouriteIds
            let result = try? await WatchAPI.currentPollutants(stationIds: ids)
            fetched = result ?? []
            if configuration.station == .station,
               WidgetStationChoice.isGone(chosenId: id, fetchedIds: fetched.map(\.stationId), fetchSucceeded: result != nil) {
                // The chosen station no longer exists: show the closest.
                WatchStore.dropReading(stationId: id)
                leadingId = nil
            } else {
                hasNewData = !fetched.isEmpty
                primary = fetched.first { $0.stationId == id }
                reading = primary.map(WatchReading.init)
                    ?? Self.cachedFavourite(id) ?? reading
                if let primary, !favouriteIds.contains(id) {
                    WatchStore.cacheChosenReading(WatchReading(primary))
                }
            }
        }
        if leadingId == nil {
            // The app resolves home from the reader's location; the extension
            // can't, so it follows whichever station the app last showed.
            // Before the app has ever run, that is the 中正 default.
            let pollutant: Pollutant?
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
            // Falls back to the cached reading when offline rather than
            // blanking the widget.
            if let pollutant {
                reading = WatchReading(pollutant)
                WatchStore.latestReading = reading
            }
            hasNewData = pollutant != nil || !fetched.isEmpty
            primary = pollutant
        }

        let savedIds = Set(WatchStore.favouriteStationIds)
        WatchStore.cacheFavouriteReadings(fetched.filter { savedIds.contains($0.stationId) }.map(WatchReading.init))

        // New readings send the widget back to its own station (FOX-76);
        // offline, the page stays. A cycled index stays either way. Read the
        // state again: a ‹ › or index tap during the fetch is newer and stays.
        if let key {
            let current = WidgetPageStore.state(for: key, in: defaults)
            state = WidgetPaging.afterFetch(current, readBefore: state, hasNewData: hasNewData, now: now)
            WidgetPageStore.save(state, for: key, in: defaults)
        }

        // Locked widgets still fetch, so the stations they tease are current.
        // Buying Pro reloads every timeline (`WidgetBridge.publish(isPro:)`).
        let previous = reading.flatMap(WatchStore.recordForRelevance)
        let score = WidgetRelevance.score(
            for: reading, airIndexType: configuration.index.airIndexType, previous: previous,
            alertThreshold: reading.flatMap { WatchStore.alertThresholds[$0.stationId] },
            isLocked: isLocked, now: now
        )
        let relevance = TimelineEntryRelevance(score: score, duration: Self.refreshInterval)
        // Extra large only: history, forecast and cam, fetched together,
        // each falling back to its last good copy.
        var detail: WidgetStationDetail?
        var camFrame: UIImage?
        if WidgetFamilyRules.showsStationDetail(context.family), let stationId = reading?.stationId {
            let place = primary.flatMap { $0.stationId == stationId ? WidgetStationDetail.Place($0) : nil }
            (detail, camFrame) = await StationDetailLoader.refresh(stationId: stationId, place: place)
        }
        func entry(at date: Date) -> ReadingEntry {
            var made = Self.makeEntry(
                date: date, leading: reading, configuration: configuration, family: context.family,
                isPreview: context.isPreview, isLocked: isLocked, state: state, relevance: relevance
            )
            made.detail = detail
            made.camFrame = camFrame
            return made
        }
        return Timeline(entries: Self.entriesWithReset(entry(at: now), state: state, now: now, entry: entry),
                        policy: .after(next))
    }

    /// `shown`, then the widget's own station again when a paged widget's
    /// 30 minutes run out, so the return happens on every timeline, offline
    /// ones included, not only after a tap.
    private static func entriesWithReset(
        _ shown: ReadingEntry, state: WidgetPageState, now: Date, entry: (Date) -> ReadingEntry
    ) -> [ReadingEntry] {
        guard shown.showsPager, let reset = WidgetPaging.resetDate(state, pageIds: shown.pageIds, now: now) else {
            return [shown]
        }
        return [shown, entry(reset)]
    }

    /// The reload after a tap: the page or index it chose, from saved
    /// readings, then the widget's own station again `WidgetPaging.resetInterval`
    /// after the tap. The next fetch stays when the last one planned it.
    private static func tapTimeline(
        configuration: SelectIndexIntent, context: Context, isLocked: Bool, state: WidgetPageState, now: Date
    ) -> Timeline<ReadingEntry> {
        let leading = cachedLeadingReading(for: configuration)
        // Relevance follows the widget's own station, as a refresh scores it.
        let score = WidgetRelevance.score(
            for: leading, airIndexType: configuration.index.airIndexType,
            previous: leading.flatMap { WidgetRelevance.previous(of: $0, in: WatchStore.relevanceHistory) },
            alertThreshold: leading.flatMap { WatchStore.alertThresholds[$0.stationId] },
            isLocked: isLocked, now: now
        )
        let relevance = TimelineEntryRelevance(score: score, duration: refreshInterval)

        func entry(at date: Date) -> ReadingEntry {
            makeEntry(
                date: date, leading: leading, configuration: configuration, family: context.family,
                isPreview: context.isPreview, isLocked: isLocked, state: state, relevance: relevance
            )
        }

        let entries = entriesWithReset(entry(at: now), state: state, now: now, entry: entry)
        let nextRefresh = max(
            (state.refreshedAt ?? now).addingTimeInterval(refreshInterval), now.addingTimeInterval(60)
        )
        return Timeline(entries: entries, policy: .after(nextRefresh))
    }
}

struct ReadingWidgetView: View {
    let entry: ReadingEntry

    @Environment(\.widgetFamily) private var family
    /// False in StandBy, which drops the container background.
    @Environment(\.showsWidgetContainerBackground) private var showsContainerBackground
    /// `.vibrant` in StandBy at night (and on the Lock Screen): colour turns
    /// to shades of one tint, so it can't carry the level by itself.
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var type: AirIndexTypes { entry.airIndexType }

    var body: some View {
        Group {
            if let reading = entry.reading {
                if entry.isLocked {
                    content(reading)
                        .overlay(alignment: .bottom) { proBanner }
                } else {
                    content(reading)
                }
            } else if entry.isLocked {
                proOnly
            } else {
                empty
            }
        }
        .widgetURL(tapURL)
    }

    /// Locked medium / large / extra large: a tap opens the app on the Pro screen. Unlocked
    /// medium / large open the station shown, the page paged to included
    /// (FOX-76). The other sizes open the app as before.
    private var tapURL: URL? {
        if entry.isLocked { return DeepLink.proURL(source: .widgetLocked) }
        guard ReadingProvider.pagesFavourites(in: family),
              let stationId = entry.reading?.stationId, stationId > 0
        else { return nil }
        return DeepLink.stationURL(stationId: stationId, source: .widget)
    }

    @ViewBuilder
    private func content(_ reading: WatchReading) -> some View {
        let status = reading.status(type)
        let tint = Color(status.getColor())
        let value = reading.formatted(type)

        switch family {
        // One station in detail, never a favourites list (FOX-72).
        case .systemExtraLarge:
            StationDetailWidgetView(
                reading: reading, type: type, detail: entry.detail, camFrame: entry.camFrame,
                isLocked: entry.isLocked
            )

        // StandBy shows the small widget full screen, read from across the
        // room: the leading station only, big, with its level in words.
        case .systemSmall where !showsContainerBackground:
            standBy(reading)

        case .systemSmall where !entry.favourites.isEmpty:
            smallWithFavourites(reading)

        // The ‹ › buttons live in this layout, so a page whose side list
        // is empty keeps it.
        case .systemMedium where !entry.favourites.isEmpty || entry.showsPager:
            mediumWithFavourites(reading)

        // With nothing saved, large says how to add favourites rather than
        // falling back to the plain layout.
        case .systemLarge where entry.listsFavourites:
            largeWithFavourites(reading)

        case .systemSmall:
            VStack(alignment: .leading, spacing: 4) {
                indexLabel()
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
                        indexValue(value, unit: true)
                            .font(.title2.monospacedDigit().weight(.semibold))
                        Spacer(minLength: 0)
                        if !reading.publishTime.isEmpty {
                            Text(verbatim: reading.publishTime)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        indexValue(value, unit: false)
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
                            .proBlurred(entry.isLocked)
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

    // MARK: - StandBy

    /// No background of its own: StandBy puts it on black. The level is in
    /// words as well as in the bar's colour, so it still reads in night mode's
    /// single red tint, where the bar is drawn plain.
    private func standBy(_ reading: WatchReading) -> some View {
        let status = reading.status(type)
        let tint = Color(status.getColor())
        let fullColor = renderingMode == .fullColor

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                indexLabel()
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if status.hasFaceImage {
                    Image(status.getImage())
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
            }
            Text(verbatim: reading.formatted(type))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            // The band's colour on its own bar, not on the number: very
            // unhealthy and hazardous are too dark to read on black.
            Capsule()
                .fill(fullColor ? tint : Color.primary)
                .frame(height: 6)
                .widgetAccentable()
            Text(status.toString())
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Text(reading.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Favourites

    private func smallWithFavourites(_ reading: WatchReading) -> some View {
        let status = reading.status(type)
        let foreground = Color(status.getForegroundColor())

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        indexLabel()
                        Text(reading.displayName)
                            .lineLimit(1)
                    }
                    .font(.caption2.weight(.semibold))
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
                detailLine(reading)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 6) {
                    indexValue(reading.formatted(type), unit: false)
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
                favouriteRows(limit: entry.showsPager ? 2 : 3, showsStatus: false)
                Spacer(minLength: 0)
                if entry.showsPager {
                    pager
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
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
                    indexValue(value, unit: true)
                        .font(.title2.monospacedDigit().weight(.semibold))
                }
                Spacer(minLength: 0)
                face(status, value: value, size: 72)
            }

            detailLine(reading)
            otherIndices(reading)

            Divider()

            HStack(spacing: 6) {
                Text("Widget.favourites")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if entry.showsPager {
                    pager
                }
            }
            if entry.favourites.isEmpty {
                Text("Widget.no_favourites")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                favouriteRows(limit: 4, showsStatus: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(4)
    }

    // MARK: - Buttons (FOX-76)

    /// The index's name. Tapping it steps to the next index
    /// (`WidgetPaging.indexCycle`), except on a locked widget.
    @ViewBuilder
    private func indexLabel() -> some View {
        if entry.cyclesIndex, let key = entry.widgetKey,
           let next = IndexOption(rawValue: WidgetPaging.nextIndex(after: type).rawValue) {
            Button(intent: CycleWidgetIndexIntent(widgetKey: key, index: next)) {
                Text(verbatim: type.toString())
                    .padding(.horizontal, 4)
                    .background(Color.primary.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Widget.show_index \(next.airIndexType.toString())"))
        } else {
            Text(verbatim: type.toString())
        }
    }

    /// "AQI 42", or "PM2.5 17 μg/m3" with `unit`: the label cycles the index.
    private func indexValue(_ value: String, unit: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            indexLabel()
            Text(verbatim: unit ? "\(value) \(type.getUnit())".trimmingCharacters(in: .whitespaces) : value)
                .proBlurred(entry.isLocked)
        }
    }

    /// ‹ 2 / 5 ›: steps through the widget's station and the favourites,
    /// wrapping at both ends.
    @ViewBuilder
    private var pager: some View {
        if let key = entry.widgetKey {
            let count = entry.pageIds.count
            HStack(spacing: 6) {
                pageButton(key: key, step: -1, systemName: "chevron.left", label: "Widget.previous_station")
                Text(verbatim: "\(entry.page + 1) / \(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Widget.page_position \(entry.page + 1) \(count)"))
                pageButton(key: key, step: 1, systemName: "chevron.right", label: "Widget.next_station")
            }
        }
    }

    private func pageButton(key: String, step: Int, systemName: String, label: LocalizedStringKey) -> some View {
        let page = WidgetPaging.page(from: entry.page, step: step, count: entry.pageIds.count)
        return Button(intent: ShowWidgetPageIntent(
            widgetKey: key, stationId: WidgetPaging.target(ofPage: page, in: entry.pageIds)
        )) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: - Station detail

    /// "Main pollutant: PM2.5 · 11/4 10:00": what MOENV names past good, and
    /// when the reading was published, in Taiwan time.
    @ViewBuilder
    private func detailLine(_ reading: WatchReading) -> some View {
        let pollutant = AirQualityAnswer.mainPollutant(of: reading)
        let updated = Self.updatedText(reading)
        if pollutant != nil || updated != nil {
            HStack(spacing: 4) {
                if let pollutant {
                    Text("Forecast.major_pollutant \(pollutant.toString())")
                        .proBlurred(entry.isLocked)
                }
                if pollutant != nil, updated != nil {
                    Text(verbatim: "·")
                }
                if let updated {
                    Text(verbatim: updated)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    /// Large: the indices other than the one shown, each in its level's tint.
    private func otherIndices(_ reading: WatchReading) -> some View {
        HStack(spacing: 4) {
            ForEach(WidgetPaging.indexCycle.filter { $0 != type }, id: \.self) { other in
                VStack(spacing: 1) {
                    Text(verbatim: other.toString())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(verbatim: reading.formatted(other))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .proBlurred(entry.isLocked)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    Color(reading.status(other).getColor()).opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
        }
    }

    /// `publish_time` is Taiwan local time; shown as such whatever the
    /// device's zone.
    private static let updatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        return formatter
    }()

    private static func updatedText(_ reading: WatchReading) -> String? {
        guard !reading.publishTime.isEmpty else { return nil }
        return WatchStore.publishedDate(of: reading).map(updatedFormatter.string(from:)) ?? reading.publishTime
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
                .proBlurred(entry.isLocked)
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
                    .proBlurred(entry.isLocked)
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
            case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge:
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

    /// Over a locked widget's blurred numbers. Tapping opens the Pro screen.
    private var proBanner: some View {
        Label {
            Text("Widget.pro_unlock")
        } icon: {
            Image(systemName: "lock.fill")
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.systemBackground).opacity(0.9), in: Capsule())
    }

    /// Medium, large and extra large without Pro and with no reading yet to tease.
    private var proOnly: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Widget.pro_only_title")
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(.headline)
            Text("Widget.pro_only_body")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }
}

extension View {
    /// Blurs a reading on a locked widget, and keeps VoiceOver from reading it.
    func proBlurred(_ isLocked: Bool) -> some View {
        blur(radius: isLocked ? 6 : 0)
            .accessibilityHidden(isLocked)
    }

    /// The language chosen in the app under Help, as the app's root view
    /// applies it, so `Text("Key")` and status names follow it. Left to the
    /// system when no choice is made.
    @ViewBuilder
    func appLanguageLocale() -> some View {
        if let identifier = AppLanguage.current.localeIdentifier {
            environment(\.locale, Locale(identifier: identifier))
        } else {
            self
        }
    }

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
    static func preview(favourites: [WatchReading] = WatchReading.placeholderFavourites, isLocked: Bool = false) -> ReadingEntry {
        ReadingEntry(
            date: Date(), reading: .placeholder, airIndexType: .aqi,
            listsFavourites: true, favourites: favourites, isLocked: isLocked
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

#Preview("Large", as: .systemLarge) {
    TWAQIWidget()
} timeline: {
    ReadingEntry.preview()
    ReadingEntry.preview(favourites: [])
}

#Preview("Medium · no Pro", as: .systemMedium) {
    TWAQIWidget()
} timeline: {
    ReadingEntry.preview(isLocked: true)
    ReadingEntry(date: Date(), reading: nil, airIndexType: .aqi, isLocked: true)
}

#Preview("Large · no Pro", as: .systemLarge) {
    TWAQIWidget()
} timeline: {
    ReadingEntry.preview(isLocked: true)
    ReadingEntry(date: Date(), reading: nil, airIndexType: .aqi, isLocked: true)
}

#Preview("Extra large", as: .systemExtraLarge) {
    TWAQIWidget()
} timeline: {
    ReadingEntry(date: Date(), reading: .placeholder, airIndexType: .aqi, detail: .placeholder)
    ReadingEntry(date: Date(), reading: .placeholder, airIndexType: .pm25, detail: .placeholder)
    // Every extra source failed and nothing is saved: the header, indices
    // and wind still show.
    ReadingEntry(date: Date(), reading: .placeholder, airIndexType: .aqi)
}

#Preview("Extra large · no Pro", as: .systemExtraLarge) {
    TWAQIWidget()
} timeline: {
    ReadingEntry(date: Date(), reading: .placeholder, airIndexType: .aqi, isLocked: true, detail: .placeholder)
    ReadingEntry(date: Date(), reading: nil, airIndexType: .aqi, isLocked: true)
}
#endif
