//
//  PollutantHistorySeries.swift
//  TWAQI
//
//  Created by kf on 21/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// How far back a pollutant history chart reaches.
enum HistoryRange: String, CaseIterable, Identifiable {
    case day
    case week

    var id: String { rawValue }

    /// Hourly readings the range spans.
    var hours: Int {
        switch self {
        case .day: return 24
        case .week: return 7 * 24
        }
    }
}

/// One clock hour of a series. `value` is nil when the station reported nothing
/// that hour: the chart draws a gap there, never a zero.
struct HistorySample: Equatable {
    let time: Date
    let value: Double?
}

/// One pollutant's readings sliced to a range, on a fixed hourly grid.
///
/// Lives outside the view so range slicing and gap handling can be tested.
/// The grid is what makes gaps honest: a reading that never arrived is an
/// empty slot, not a shorter list that the chart would quietly join up.
struct PollutantHistorySeries: Equatable {
    /// What the history request asks for: a full week of hours. The API
    /// returns at most what it keeps, which may be less.
    static let fetchLimit = HistoryRange.week.hours

    let range: HistoryRange
    /// Oldest first, one per clock hour, ending on the newest reading's hour.
    /// Starts at the range's start, or at the oldest reading when the history
    /// doesn't reach back that far.
    let samples: [HistorySample]

    /// Builds the series for `airIndexType` from readings in any order.
    ///
    /// - The window ends on the newest reading, not on "now", so a station
    ///   opened offline charts the history it has.
    /// - A reading of zero or less is a gap: several stations report 0.0 for
    ///   what they don't measure.
    /// - Readings whose time can't be parsed are dropped.
    static func make(
        readings: [HistoricalPollutant],
        airIndexType: AirIndexTypes,
        range: HistoryRange
    ) -> PollutantHistorySeries {
        var byHour: [Int: Double?] = [:]
        for reading in readings {
            guard let date = Date.fromApi(reading.publishTime) else { continue }
            let value = reading.getValue(airIndexType: airIndexType)
            // The newest reading in an hour wins, in input order.
            byHour[hourIndex(date)] = value > 0 ? value : nil
        }

        guard let newest = byHour.keys.max(), let oldest = byHour.keys.min() else {
            return PollutantHistorySeries(range: range, samples: [])
        }

        let first = max(newest - (range.hours - 1), oldest)
        let samples = (first...newest).map { hour in
            HistorySample(time: date(hourIndex: hour), value: byHour[hour] ?? nil)
        }
        return PollutantHistorySeries(range: range, samples: samples)
    }

    // MARK: - Reading the series

    var values: [Double] { samples.compactMap(\.value) }

    /// Enough readings to draw a line.
    var isChartable: Bool { values.count >= 2 }

    var lowest: HistorySample? {
        samples.filter { $0.value != nil }.min { ($0.value ?? 0) < ($1.value ?? 0) }
    }

    var highest: HistorySample? {
        samples.filter { $0.value != nil }.max { ($0.value ?? 0) < ($1.value ?? 0) }
    }

    /// The newest hour that has a reading.
    var latest: HistorySample? {
        samples.last { $0.value != nil }
    }

    /// Hours the series covers, which is less than the range when the history
    /// is shorter than it.
    var coveredHours: Int { samples.count }

    /// The history doesn't reach back as far as the range asks for.
    var isShorterThanRange: Bool { samples.count < range.hours }

    /// Runs of consecutive sample indexes that have a reading. A gap ends a
    /// run, so a line is never drawn across missing hours.
    var runs: [[Int]] {
        var runs: [[Int]] = []
        var current: [Int] = []
        for (index, sample) in samples.enumerated() {
            if sample.value != nil {
                current.append(index)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// The sample under a horizontal position, `fraction` 0 (oldest) to 1
    /// (newest). Out-of-range positions clamp to the ends.
    func index(atFraction fraction: Double) -> Int? {
        guard !samples.isEmpty else { return nil }
        guard samples.count > 1 else { return 0 }
        let clamped = min(1, max(0, fraction))
        return Int((clamped * Double(samples.count - 1)).rounded())
    }

    // MARK: - Hour arithmetic

    /// Taiwan has no daylight saving and its offset is a whole number of
    /// hours, so hours since the epoch line up with Taiwan clock hours.
    private static func hourIndex(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 3600).rounded(.down))
    }

    private static func date(hourIndex: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(hourIndex) * 3600)
    }
}
