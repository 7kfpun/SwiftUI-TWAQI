//
//  ForecastStrip.swift
//  TWAQI
//
//  Created by kf on 22/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// The part of the Taiwan day a weather cell covers (TWAQ-12). CWA forecasts in
/// 12-hour periods (06–18, 18–06), so the strip shows them as these four
/// six-hour parts rather than as invented hourly values.
enum DayPart: String, CaseIterable, Equatable {
    /// 06–12
    case morning
    /// 12–18
    case afternoon
    /// 18–24
    case evening
    /// 00–06
    case night

    static let length = 6

    /// The part a Taiwan clock hour (0–23) falls in.
    static func of(hour: Int) -> DayPart {
        switch hour {
        case 6..<12: return .morning
        case 12..<18: return .afternoon
        case 18..<24: return .evening
        default: return .night
        }
    }

    var localizationKey: String { "Strip.part.\(rawValue)" }

    var isNight: Bool { self == .evening || self == .night }
}

/// One cell of the strip's weather row: a day part with the CWA period it
/// belongs to. Temperature and rain chance are the period's, so the two
/// halves of one period read the same: nothing here is hourly.
struct WeatherStripCell: Equatable {
    let part: DayPart
    let start: Date
    let end: Date
    let wx: Int?
    let text: String?
    /// Chance of rain, %.
    let pop: Double?
    let minT: Double?
    let maxT: Double?
}

/// The strip's AQI chart: what was observed, then what the 空品區 forecast
/// says. The forecast is one value per day, so it is drawn as day spans,
/// never as hourly points.
struct StripAqiTrend: Equatable {
    struct Point: Equatable {
        let time: Date
        let aqi: Double
    }

    /// One forecast day clipped to the chart's window.
    struct Span: Equatable {
        let start: Date
        let end: Date
        let aqi: Int
        /// `yyyy-MM-dd`, the Taiwan day.
        let day: String
    }

    let windowStart: Date
    let now: Date
    let windowEnd: Date
    /// Oldest first, hourly readings from `windowStart` to `now`.
    let observed: [Point]
    /// Soonest first, from `now` to `windowEnd`.
    let forecast: [Span]

    /// Consecutive hourly readings. A missing hour breaks the line, as in the
    /// history chart, so a gap never reads as a straight stretch between its
    /// neighbours. A run of one is drawn as a dot.
    var observedRuns: [[Point]] {
        var runs: [[Point]] = []
        for point in observed {
            if let last = runs.last?.last, point.time.timeIntervalSince(last.time) <= 3600 + 1 {
                runs[runs.count - 1].append(point)
            } else {
                runs.append([point])
            }
        }
        return runs
    }

    /// Enough to draw: a line, or at least one forecast day.
    var isChartable: Bool { observed.count >= 2 || !forecast.isEmpty }
}

enum ForecastStrip {
    /// The window ahead of now the strip covers.
    static let horizonHours = 24
    /// How far back observed readings are drawn.
    static let lookbackHours = 12

    // MARK: Weather

    /// The CWA periods cut into day-part cells, from `now` to `now` + 24 h,
    /// oldest first. A cell that has already ended is dropped; the one
    /// running now keeps its real start. Periods without parseable times are
    /// ignored.
    static func weatherCells(_ periods: [WeatherPeriod], now: Date = Date()) -> [WeatherStripCell] {
        let calendar = WeatherDates.calendar
        let windowEnd = now.addingTimeInterval(TimeInterval(horizonHours * 3600))

        var cells: [WeatherStripCell] = []
        for period in periods.sorted(by: { $0.start < $1.start }) {
            guard let periodStart = period.startDate, let periodEnd = period.endDate, periodEnd > periodStart else { continue }

            var cursor = periodStart
            while cursor < periodEnd {
                let hour = calendar.component(.hour, from: cursor)
                let part = DayPart.of(hour: hour)
                let boundary = calendar.nextDate(
                    after: cursor,
                    matching: DateComponents(hour: ((hour / DayPart.length) + 1) * DayPart.length % 24, minute: 0, second: 0),
                    matchingPolicy: .nextTime
                ) ?? periodEnd
                let end = min(boundary, periodEnd)

                if end > now, cursor < windowEnd {
                    cells.append(WeatherStripCell(
                        part: part, start: cursor, end: end,
                        wx: period.wx, text: period.text, pop: period.pop,
                        minT: period.minT, maxT: period.maxT
                    ))
                }
                cursor = end
            }
        }
        // Overlapping periods (a feed hiccup) would double a part: keep the first.
        var seen = Set<Date>()
        return cells.filter { seen.insert($0.start).inserted }
    }

    /// 「11/23」 for a cell that starts on a later Taiwan day than `now`, so
    /// the two "Night"s or "Morning"s of a 24-hour window can be told apart;
    /// nil for today's cells.
    static func dateLabel(_ cell: WeatherStripCell, now: Date = Date()) -> String? {
        guard WeatherDates.day(cell.start) != WeatherDates.day(now) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = WeatherDates.taipei
        formatter.dateFormat = "M/d"
        return formatter.string(from: cell.start)
    }

    // MARK: AQI

    /// Observed AQI for the last `lookbackHours` and the forecast days up to
    /// `horizonHours` ahead, on Taiwan time.
    ///
    /// - Readings of zero or less are gaps, as in the history charts.
    /// - Forecast days without an AQI value are left out.
    static func aqiTrend(
        readings: [HistoricalPollutant],
        days: [AqiForecast],
        now: Date = Date()
    ) -> StripAqiTrend {
        let windowStart = now.addingTimeInterval(-TimeInterval(lookbackHours * 3600))
        let windowEnd = now.addingTimeInterval(TimeInterval(horizonHours * 3600))

        // A reading a few minutes ahead of the device clock is tolerated.
        let series = PollutantHistorySeries.make(readings: readings, airIndexType: .aqi, range: .day)
        let observed = series.samples.compactMap { sample -> StripAqiTrend.Point? in
            guard let value = sample.value, sample.time >= windowStart, sample.time <= now.addingTimeInterval(600) else { return nil }
            return StripAqiTrend.Point(time: sample.time, aqi: value)
        }

        let calendar = AqiForecastDates.calendar
        let forecast = days
            .sorted { $0.forecastDate < $1.forecastDate }
            .compactMap { day -> StripAqiTrend.Span? in
                guard
                    let aqi = day.aqi, aqi > 0,
                    let dayStart = AqiForecastDates.parseDay(day.forecastDate),
                    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
                else { return nil }
                let start = max(dayStart, now)
                let end = min(dayEnd, windowEnd)
                guard end > start else { return nil }
                return StripAqiTrend.Span(start: start, end: end, aqi: aqi, day: day.forecastDate)
            }

        return StripAqiTrend(windowStart: windowStart, now: now, windowEnd: windowEnd, observed: observed, forecast: forecast)
    }
}
