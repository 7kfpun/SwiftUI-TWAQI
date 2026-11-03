//
//  TWAQIWatchWidget.swift
//  TWAQIWatchWidget
//
//  Created by kf on 20/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import AppIntents
import os
import SwiftUI
import WidgetKit

/// Watch-face complications for the station chosen in the watch app.
///
/// Replaces the old ClockKit data source; WidgetKit accessory families cover
/// the circular, corner, rectangular and inline slots on current faces.
@main
struct TWAQIWatchWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SelectIndexIntent.widgetKind, intent: SelectIndexIntent.self, provider: ReadingProvider()) { entry in
            ReadingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Watch.widget_name")
        .description("Watch.widget_description")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct ReadingEntry: TimelineEntry {
    let date: Date
    let reading: WatchReading?
    let airIndexType: AirIndexTypes
    var style: ComplicationStyle = .labelled
    var showsStation = true
    /// Without Pro the face drops its number and the other styles show a
    /// lock, not the reading.
    var access: ComplicationAccess = .full
    /// How far up the Smart Stack this entry should go (`WidgetRelevance`).
    var relevance: TimelineEntryRelevance?

    var isLocked: Bool { access == .locked }
}

struct ReadingProvider: AppIntentTimelineProvider {
    /// Readings are published hourly; half that keeps a complication at most
    /// one publish behind without spending the refresh budget.
    private static let refreshInterval: TimeInterval = 30 * 60

    private static let log = Logger(subsystem: "com.kfpun.twaqi.watchwidget", category: "pro")

    func placeholder(in context: Context) -> ReadingEntry {
        ReadingEntry(date: Date(), reading: .placeholder, airIndexType: .aqi)
    }

    /// Also the face picker's preview, so a Pro style shows "Pro" there
    /// before it is added, not only after. The cached answer: a snapshot has
    /// to come back quickly.
    func snapshot(for configuration: SelectIndexIntent, in context: Context) async -> ReadingEntry {
        let access = ComplicationAccess(style: configuration.style, isPro: WatchPro.isUnlocked)
        return ReadingEntry(
            date: Date(),
            reading: access == .locked ? nil : WatchStore.latestReading ?? .placeholder,
            airIndexType: configuration.index.airIndexType,
            style: configuration.style, showsStation: configuration.showsStation, access: access
        )
    }

    func timeline(for configuration: SelectIndexIntent, in context: Context) async -> Timeline<ReadingEntry> {
        let now = Date()
        let next = now.addingTimeInterval(Self.refreshInterval)
        // The free face still gets its reading; only the Pro styles lock.
        // The app reloads every timeline the moment a purchase lands.
        let isPro = await WatchPro.refresh()
        let access = ComplicationAccess(style: configuration.style, isPro: isPro)
        guard access != .locked else {
            // The watch has no Firebase Analytics; this is the locked-style
            // event, in the unified log (FOX-63, FOX-44).
            Self.log.notice(
                "watch_complication_locked style=\(configuration.style.rawValue, privacy: .public) family=\(String(describing: context.family), privacy: .public) index=\(configuration.index.rawValue, privacy: .public)"
            )
            // A lock is never pushed up the Smart Stack.
            await SmartStackHints.update(isPro: false, now: now)
            let entry = ReadingEntry(
                date: now, reading: nil, airIndexType: configuration.index.airIndexType,
                style: configuration.style, showsStation: configuration.showsStation, access: access,
                relevance: TimelineEntryRelevance(score: 0, duration: Self.refreshInterval)
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

        // The watch has no copy of the phone's alerts, so no threshold here.
        let previous = reading.flatMap(WatchStore.recordForRelevance)
        // The Smart Stack is part of Pro: the free face is never lifted.
        let score = WidgetRelevance.score(
            for: reading, airIndexType: configuration.index.airIndexType, previous: previous,
            isLocked: !isPro, now: now
        )
        await SmartStackHints.update(isPro: isPro, now: now)

        let entry = ReadingEntry(
            date: now, reading: reading, airIndexType: configuration.index.airIndexType,
            style: configuration.style, showsStation: configuration.showsStation, access: access,
            relevance: TimelineEntryRelevance(score: score, duration: Self.refreshInterval)
        )
        return Timeline(entries: [entry], policy: .after(next))
    }

    /// watchOS has no editor for intent parameters on the face, so each index
    /// is offered as its own complication in the picker, once per style,
    /// with and without the station name. Every style but the free face is
    /// marked Pro in its name, so nobody meets the lock as a surprise.
    func recommendations() -> [AppIntentRecommendation<SelectIndexIntent>] {
        IndexOption.allCases.flatMap { option in
            let name = option.airIndexType.toString()
            let styles: [(ComplicationStyle, String)] = [
                (.labelled, name),
                (.numberOnly, String(localized: "Watch.widget_short \(name)")),
                (.face, String(localized: "Watch.widget_face \(name)")),
                (.status, String(localized: "Watch.widget_status \(name)")),
            ]
            // Plain strings only: WidgetKit traps on a localized Text with an
            // interpolated argument as a description, and the extension dies
            // before the face picker gets any of its complications.
            return styles.flatMap { style, title in
                let marked = { (title: String) in
                    style.isPro ? String(localized: "Watch.widget_pro \(title)") : title
                }
                return [
                    AppIntentRecommendation(
                        intent: SelectIndexIntent(index: option, style: style),
                        description: Text(verbatim: marked(title))
                    ),
                    AppIntentRecommendation(
                        intent: SelectIndexIntent(index: option, style: style, showsStation: false),
                        description: Text(verbatim: marked(String(localized: "Watch.widget_no_station \(title)")))
                    ),
                ]
            }
        }
    }
}

struct ReadingWidgetView: View {
    let entry: ReadingEntry

    @Environment(\.widgetFamily) private var family

    private var type: AirIndexTypes { entry.airIndexType }
    private var style: ComplicationStyle { entry.style }
    private var showsLabel: Bool { style == .labelled }
    /// False for the free face, which never draws the number.
    private var showsNumber: Bool { entry.access.showsNumber }

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
        case .accessoryCircular where style == .face:
            // The face fills the slot; the ring still tracks the band. A
            // drawn ring, not a Gauge: on the face a capacity gauge with no
            // labels draws grey placeholders over the image.
            ZStack {
                ring(status, tint: tint)

                face(status)
                    .frame(width: 30, height: 30)
                    .foregroundStyle(tint)
                    .widgetAccentable()
            }

        case .accessoryCircular where style == .status:
            ZStack {
                ring(status, tint: tint)

                // "Unhealthy for sensitive groups" has to fit too. A line per
                // word makes long words shrink instead of breaking mid-word.
                Text(status.toString())
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(statusLines(status))
                    .minimumScaleFactor(0.4)
                    .padding(7)
            }

        case .accessoryCircular:
            gauge(status, value: value, tint: tint)
                .gaugeStyle(.accessoryCircular)

        case .accessoryCorner where style == .face:
            // Without Pro the curve names the index instead of the number,
            // so a PM2.5 face isn't read as the AQI.
            face(status)
                .padding(4)
                .widgetLabel {
                    Text(verbatim: showsNumber ? value : type.toString())
                }

        case .accessoryCorner where style == .status:
            Image(systemName: "aqi.medium")
                .font(.title3)
                .foregroundStyle(tint)
                .widgetAccentable()
                .widgetLabel {
                    Text(status.toString())
                }

        case .accessoryCorner:
            // Small enough that "AQI 59" or "PM2.5 7" fits along the curve.
            Text(verbatim: showsLabel ? "\(type.toString()) \(value)" : value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .widgetCurvesContent()
                .widgetLabel {
                    gauge(status, value: value, tint: tint)
                }

        case .accessoryRectangular:
            HStack(spacing: 6) {
                // The face style gives the face the height of the slot.
                if style == .face {
                    face(status)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(tint)
                        .widgetAccentable()
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        if style != .face && status.hasFaceImage {
                            Image(status.getImage())
                                .resizable()
                                .frame(width: 18, height: 18)
                        }

                        Text(status.toString())
                            .font(.headline)
                            // Shrinks rather than cuts "Unhealthy for sensitive
                            // groups"; the status style has a spare line to wrap.
                            .lineLimit(style == .status ? 2 : 1)
                            .minimumScaleFactor(style == .status ? 0.8 : 0.4)
                    }
                    .foregroundStyle(tint)
                    .widgetAccentable()

                    // The status style names the index, so a PM2.5 level isn't
                    // read as the AQI.
                    if style == .status {
                        Text(verbatim: entry.showsStation
                            ? "\(type.toString()) · \(reading.displayName)"
                            : type.toString())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: numberLine(value))
                            .monospacedDigit()

                        if entry.showsStation {
                            Text(reading.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            let station = entry.showsStation ? " · \(reading.displayName)" : ""
            if style == .status {
                Text(status.toString()) + Text(verbatim: station)
            } else if showsNumber {
                // Inline can't draw the face, so the face style keeps the label.
                let text = style == .numberOnly ? value : "\(type.toString()) \(value)"
                Text(verbatim: text + station)
            } else {
                // The free face, where only text fits: the index and its level
                // stand in for the face, still without the number.
                Text(verbatim: "\(type.toString()) ") + Text(status.toString()) + Text(verbatim: station)
            }
        }
    }

    /// The rectangular slot's second line. The free face names the index
    /// only; the face beside it shows the level.
    private func numberLine(_ value: String) -> String {
        if !showsNumber {
            return type.toString()
        }
        return style == .numberOnly ? value : "\(type.toString()) \(value) \(type.getUnit())"
    }

    /// Fills by health band rather than raw value. Each index has its own units
    /// and breakpoints, so a band is the one scale that reads the same for AQI
    /// and for CO in ppm.
    private func gauge(_ status: AirStatuses, value: String, tint: Color) -> some View {
        Gauge(value: bandProgress(status), in: 0...1) {
            if showsLabel {
                Text(verbatim: type.toString())
            }
        } currentValueLabel: {
            Text(value)
        }
        .tint(tint)
    }

    /// English wraps between words, up to four lines; Chinese has no spaces
    /// and reads fine broken anywhere.
    private func statusLines(_ status: AirStatuses) -> Int {
        guard !Locale.isChinese else { return 2 }
        // Built first: an interpolated literal would look up "AirStatus.%@".
        let key = "AirStatus.\(status.rawValue)"
        let words = String(localized: String.LocalizationValue(key)).split(separator: " ").count
        return min(max(words, 1), 4)
    }

    /// A track with the band's share of it filled, from the top.
    private func ring(_ status: AirStatuses, tint: Color) -> some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.25), lineWidth: 4)

            Circle()
                .trim(from: 0, to: bandProgress(status))
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(2)
    }

    /// How far up the six bands this status sits, 0 to 1.
    private func bandProgress(_ status: AirStatuses) -> Double {
        let bands = AirStatuses.getShowAllCases()
        let band = bands.firstIndex(of: status).map { $0 + 1 } ?? 0
        return Double(band) / Double(bands.count)
    }

    /// The phone app's face for the band; a dash when there's no reading.
    @ViewBuilder
    private func face(_ status: AirStatuses) -> some View {
        if status.hasFaceImage {
            Image(status.getImage())
                .resizable()
                .scaledToFit()
        } else {
            Text(verbatim: "--")
        }
    }

    /// A Pro style without Pro: reads "Pro" and points the reader at the
    /// app, where the paywall is. The face style is free and never lands here.
    private var locked: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label {
                        Text(verbatim: "\(type.toString()) · Pro")
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                    .font(.headline)
                    .widgetAccentable()

                    Text("Watch.pro_locked")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryInline:
                Label("Watch.pro_locked", systemImage: "lock.fill")
            case .accessoryCorner:
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .widgetAccentable()
                    .widgetLabel {
                        Text(verbatim: "Pro")
                    }
            default:
                VStack(spacing: 0) {
                    Image(systemName: "lock.fill")
                        .font(.body)
                    Text(verbatim: "Pro")
                        .font(.system(size: 12, weight: .semibold))
                }
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
                Text(verbatim: showsLabel ? "\(type.toString()) --" : "--")
            }
        }
    }
}
