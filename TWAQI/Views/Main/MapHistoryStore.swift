//
//  MapHistoryStore.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// The past 24 hours of readings for the map's stations, for the timeline
/// scrubber.
///
/// `/v1/historical-pollutants` takes one station at a time — there is no
/// country-wide call — so a map of ~80 stations is ~80 requests of about a
/// second each. They only go out once the timeline is touched, for the stations
/// in view (nearest the centre first), at most `maxConcurrent` at a time, and
/// each station once per publish hour.
///
/// Readings are kept by their own publish hour rather than by "hours ago", so a
/// station fetched an hour back still answers correctly for every hour it
/// covers; an hour it doesn't have simply comes back `nil`.
final class MapHistoryStore {
    /// How far back the scrubber reaches.
    static let hours = 24

    /// Six keeps the whole island to a few seconds without leaning on the API
    /// with 80 requests at once.
    private static let maxConcurrent = 6

    /// Main queue, after each station's history arrives (or fails).
    var onChange: (() -> Void)?

    private var readings: [Int: [String: HistoricalPollutant]] = [:]

    /// The country's latest publish hour each station was fetched against.
    /// Failures are recorded too, so a station with no history is not retried
    /// until the next hour.
    private var fetchedAnchor: [Int: String] = [:]

    private var pending: [(stationId: Int, anchor: String)] = []
    private var inFlight: Set<Int> = []

    /// What the last `request` asked for, for the progress readout.
    private var requested: [Int: String] = [:]

    /// That hour's reading, if the station has one. `publishTime` is any
    /// `yyyy-MM-ddTHH:mm:ss` within the hour.
    func reading(stationId: Int, publishTime: String) -> HistoricalPollutant? {
        guard let hour = MapTimeline.hourKey(publishTime) else { return nil }
        return readings[stationId]?[hour]
    }

    /// Queues history for these stations, in priority order, ahead of anything
    /// still waiting from an earlier request. Stations already fetched against
    /// their anchor are skipped.
    func request(_ stations: [(stationId: Int, anchor: String)]) {
        requested = Dictionary(stations.map { ($0.stationId, $0.anchor) }, uniquingKeysWith: { first, _ in first })

        let wanted = stations.filter { fetchedAnchor[$0.stationId] != $0.anchor && !inFlight.contains($0.stationId) }
        let wantedIds = Set(wanted.map(\.stationId))
        pending = wanted + pending.filter { !wantedIds.contains($0.stationId) }

        pump()
        onChange?()
    }

    /// Stations from the last request that have finished, out of how many it
    /// asked for.
    var progress: (done: Int, total: Int) {
        let done = requested.filter { fetchedAnchor[$0.key] == $0.value }.count
        return (done, requested.count)
    }

    var isLoading: Bool {
        let progress = progress
        return progress.done < progress.total
    }

    private func pump() {
        while inFlight.count < Self.maxConcurrent, !pending.isEmpty {
            let next = pending.removeFirst()
            guard !inFlight.contains(next.stationId) else { continue }
            inFlight.insert(next.stationId)

            APIManager.getHistoricalPollutants(stationId: next.stationId, limit: Self.hours + 1) { [weak self] result in
                guard let self else { return }
                self.inFlight.remove(next.stationId)
                self.fetchedAnchor[next.stationId] = next.anchor

                if case .success(let response) = result,
                   let history = response["data"] as? HistoricalPollutants {
                    var byHour = self.readings[next.stationId] ?? [:]
                    for reading in history {
                        if let hour = MapTimeline.hourKey(reading.publishTime) {
                            byHour[hour] = reading
                        }
                    }
                    self.readings[next.stationId] = byHour
                }

                self.pump()
                self.onChange?()
            }
        }
    }
}

/// Hour arithmetic on the API's publish times.
///
/// They are wall-clock strings in the station's own country (`2026-10-31T17:00:00`,
/// no zone). They are parsed and printed in UTC purely as a fixed calendar, so
/// "three hours before" never trips over the device's time zone or DST.
enum MapTimeline {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func date(_ publishTime: String) -> Date? {
        // Some payloads carry fractional seconds or a zone suffix; the first 19
        // characters are always the wall-clock time.
        formatter.date(from: String(publishTime.prefix(19)))
    }

    /// The publish time snapped to its hour, as the cache key.
    static func hourKey(_ publishTime: String) -> String? {
        date(publishTime).map(hourKey)
    }

    static func hourKey(_ date: Date) -> String {
        let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return formatter.string(from: hour)
    }

    /// How the timeline names an hour: the clock time, prefixed 「昨天」 when it
    /// falls on the day before `anchor`, and how far back it is
    /// (「3 小時前」, or 「最新」 at the anchor itself).
    static func describe(anchor: String, hoursAgo: Int) -> (clock: String, relative: String)? {
        guard let anchorDate = date(anchor) else { return nil }
        let date = anchorDate.addingTimeInterval(-Double(hoursAgo) * 3600)
        var clock = clockFormatter.string(from: date)
        if !calendar.isDate(date, inSameDayAs: anchorDate) {
            clock = "\("Timeline.yesterday".localized) \(clock)"
        }
        let relative = hoursAgo == 0
            ? "Timeline.latest".localized
            : String(format: "Timeline.hours_ago".localized, hoursAgo)
        return (clock, relative)
    }

    static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// The publish hour `hoursAgo` before `anchor`.
    static func publishTime(_ anchor: String, hoursAgo: Int) -> String? {
        guard let date = date(anchor) else { return nil }
        return hourKey(date.addingTimeInterval(-Double(hoursAgo) * 3600))
    }
}

extension Pollutant {
    /// This station as it read at an earlier hour: identity, name and location
    /// from the live reading, values (wind included) from history.
    ///
    /// No reading means no data for that hour. Every value is then 0, which the
    /// markers and the closest-station card already show as "-" in grey.
    init(_ live: Pollutant, reading: HistoricalPollutant?, publishTime: String) {
        stationId = live.stationId
        code = live.code
        lat = live.lat
        lon = live.lon
        aqi = reading?.aqi ?? 0
        pm25 = reading?.pm25 ?? 0
        pm10 = reading?.pm10 ?? 0
        no2 = reading?.no2 ?? 0
        so2 = reading?.so2 ?? 0
        co = reading?.co ?? 0
        o3 = reading?.o3 ?? 0
        windDirection = reading?.windDirection ?? 0
        windSpeed = reading?.windSpeed ?? 0
        self.publishTime = reading?.publishTime ?? publishTime

        name = live.name
        nameLocal = live.nameLocal
        address = live.address
        area = live.area
        areaLocal = live.areaLocal
        county = live.county
        countyLocal = live.countyLocal
        township = live.township
        stationType = live.stationType
        imageUrl = live.imageUrl
    }
}
