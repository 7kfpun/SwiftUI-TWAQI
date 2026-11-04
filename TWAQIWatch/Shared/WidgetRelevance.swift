//
//  WidgetRelevance.swift
//  TWAQIWatch
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// How relevant a reading makes the TWAQI widget, so the watch Smart Stack and
/// iPhone StandBy / Home Screen Smart Rotate bring it up on a bad-air day and
/// leave it alone on a good one (FOX-75). Pure: the timeline providers feed it
/// and turn the result into a `TimelineEntryRelevance`.
///
/// **The scale.** One scale, 0 to 100, for every TWAQI widget on the iPhone
/// and on the watch, so a score means the same everywhere:
///
/// | Reading                                      | Score |
/// |----------------------------------------------|-------|
/// | No reading, no level, locked, or stale data  | 0     |
/// | Good                                         | 10    |
/// | Moderate                                     | 25    |
/// | Unhealthy for sensitive groups               | 50    |
/// | Unhealthy                                    | 70    |
/// | Very unhealthy                               | 85    |
/// | Hazardous                                    | 90    |
/// | Worse than the previous publish              | +5    |
/// | AQI at or over the station's alert threshold | 100   |
///
/// The level is that of the index the widget shows. The alert threshold is the
/// "above" alert the reader set for that station, which is always on the AQI.
/// Stale means published more than `maxDataAge` ago, or a publish time that
/// can't be read (the gallery placeholders).
enum WidgetRelevance {
    /// The top of the scale.
    static let maxScore: Float = 100

    /// Data older than this says nothing about the air now, so it scores 0.
    static let maxDataAge: TimeInterval = 3 * 60 * 60

    /// Added when the reading is worse than the previous publish. Less than the
    /// gap between two levels, so worsening never outranks the next level up.
    static let worseningBoost: Float = 5

    /// Score for a level alone.
    static func levelScore(_ status: AirStatuses) -> Float {
        switch status {
        case .good: return 10
        case .moderate: return 25
        case .unhealthyforsensitivegroup: return 50
        case .unhealthy: return 70
        case .veryunhealthy: return 85
        case .hazardous: return 90
        case .unknown: return 0
        }
    }

    /// The score for `reading` on a widget showing `airIndexType`.
    ///
    /// - Parameters:
    ///   - previous: the same station's reading from an earlier publish, if
    ///     known (`previous(of:in:)`); a rise since then is worsening.
    ///   - alertThreshold: the station's "above" alert threshold (AQI), if on.
    static func score(
        for reading: WatchReading?,
        airIndexType: AirIndexTypes,
        previous: WatchReading? = nil,
        alertThreshold: Int? = nil,
        isLocked: Bool = false,
        now: Date = Date()
    ) -> Float {
        guard let reading, !isLocked, isFresh(reading, now: now) else { return 0 }
        let status = reading.status(airIndexType)
        guard status != .unknown else { return 0 }

        if let alertThreshold, reading.aqi >= Double(alertThreshold) {
            return maxScore
        }

        var score = levelScore(status)
        if let previous, previous.stationId == reading.stationId,
           reading.value(airIndexType) > previous.value(airIndexType) {
            score += worseningBoost
        }
        return min(score, maxScore)
    }

    /// Published no more than `maxDataAge` ago. False when the publish time
    /// doesn't parse.
    static func isFresh(_ reading: WatchReading, now: Date = Date()) -> Bool {
        guard let published = WatchStore.publishedDate(of: reading) else { return false }
        return now.timeIntervalSince(published) <= maxDataAge
    }

    // MARK: - Previous publish

    /// Most readings kept by `recording(_:in:)`: two publishes each for a few
    /// stations is all a widget needs.
    static let historyLimit = 12

    /// `history` with `reading` added, keeping for each station its latest
    /// publish and the one before it. A reading of a publish already held
    /// replaces it; an older one is ignored. Most recent last.
    static func recording(_ reading: WatchReading, in history: [WatchReading]) -> [WatchReading] {
        let sameStation = history.filter { $0.stationId == reading.stationId }
        let others = history.filter { $0.stationId != reading.stationId }

        if let latest = sameStation.last, isOlder(reading, than: latest) {
            return history
        }
        // The publish already held is replaced (a corrected value); otherwise
        // the newest held becomes the previous one.
        let kept = sameStation.filter { $0.publishTime != reading.publishTime }.suffix(1)
        return Array((others + kept + [reading]).suffix(historyLimit))
    }

    /// The reading `history` holds for `reading`'s station from an earlier
    /// publish, if any.
    static func previous(of reading: WatchReading, in history: [WatchReading]) -> WatchReading? {
        history.last { $0.stationId == reading.stationId && $0.publishTime != reading.publishTime }
            .flatMap { isOlder($0, than: reading) ? $0 : nil }
    }

    /// Compared by publish time; unreadable times count as not older.
    private static func isOlder(_ lhs: WatchReading, than rhs: WatchReading) -> Bool {
        guard let left = WatchStore.publishedDate(of: lhs),
              let right = WatchStore.publishedDate(of: rhs) else { return false }
        return left < right
    }
}

/// When the watch Smart Stack should bring the TWAQI widget up, beyond its
/// score (FOX-75): commute times, near home, and just after a station crosses
/// its alert threshold. Pure; `SmartStackHints` on the watch donates them.
enum SmartStackWindows {
    /// Clock times in Taiwan, whatever zone the device is set to: a trip to
    /// work in Taipei is at 07:00 Taipei time even on a watch still on Tokyo.
    static let timeZone = TimeZone(identifier: "Asia/Taipei")!

    /// A daily window in `timeZone`, as minutes after midnight.
    struct DailyWindow: Equatable {
        let start: Int
        let end: Int

        init(from startHour: Int, _ startMinute: Int, to endHour: Int, _ endMinute: Int) {
            start = startHour * 60 + startMinute
            end = endHour * 60 + endMinute
        }
    }

    /// Morning (06:30–09:00) and evening (17:00–19:30) commutes.
    static let commutes = [
        DailyWindow(from: 6, 30, to: 9, 0),
        DailyWindow(from: 17, 0, to: 19, 30),
    ]

    /// How many days of commute windows to donate ahead. Every app launch and
    /// widget refresh donates again, so this only bridges a quiet day or two.
    static let daysAhead = 3

    /// How long after an over-threshold reading the widget stays relevant.
    static let alertDuration: TimeInterval = 2 * 60 * 60

    /// Radius of the "near home" region around the home station. Stations are
    /// a few kilometres apart, so this is roughly the station's own area.
    static let homeRadius: Double = 2_000

    /// With no alert threshold known (the watch has no copy of the phone's
    /// alerts), the alert window opens where Unhealthy for sensitive groups
    /// begins.
    static let defaultAlertThreshold = 101

    /// The commute windows from today (in Taiwan) for `days` days, minus any
    /// already over. One still running starts at its own start, not now.
    static func commuteIntervals(from now: Date, days: Int = daysAhead) -> [DateInterval] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)

        return (0..<max(days, 0)).flatMap { offset -> [DateInterval] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            return commutes.compactMap { window in
                guard let start = calendar.date(byAdding: .minute, value: window.start, to: day),
                      let end = calendar.date(byAdding: .minute, value: window.end, to: day),
                      end > now else { return nil }
                return DateInterval(start: start, end: end)
            }
        }
    }

    /// The window after `reading` crosses `threshold` (AQI): from its publish
    /// time for `alertDuration`. Nil under the threshold, when the window is
    /// already over, or when the publish time can't be read.
    static func alertInterval(for reading: WatchReading, threshold: Int, now: Date = Date()) -> DateInterval? {
        guard reading.aqi >= Double(threshold),
              let published = WatchStore.publishedDate(of: reading) else { return nil }
        let window = DateInterval(start: published, duration: alertDuration)
        return window.end > now ? window : nil
    }
}
