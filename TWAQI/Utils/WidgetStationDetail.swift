//
//  WidgetStationDetail.swift
//  TWAQI
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// What the extra-large Home Screen widget shows beyond the reading itself
/// (FOX-72): the station's county and 空品區, its last 24 hours, its area's
/// forecast and its cam. The reading stays in `WatchStore`.
///
/// Every part is optional and kept from the last good fetch, so a failed
/// history, forecast or cam request drops nothing that was already there,
/// and the widget still shows all of it offline. Each part carries when it
/// was last fetched, and goes once that is a week ago
/// (`WatchStore.maxReadingAge`), however often the others refresh.
struct WidgetStationDetail: Codable, Equatable {
    /// Where the station is, from the current-pollutants response: what the
    /// header names and what the forecast and cam joins need.
    struct Place: Codable, Equatable {
        var nameLocal: String
        var lat: Double
        var lon: Double
        var county: String?
        var countyLocal: String?
        var area: String?
        var areaLocal: String?
    }

    /// The cam joined to the station, as the manifest lists it. The frame
    /// itself is a file next to the detail (`WidgetStationDetailCache`).
    struct Cam: Codable, Equatable {
        /// MOENV's image site id, not the station id.
        var siteId: String
        /// Capture time of the saved frame.
        var time: String?
    }

    let stationId: Int
    var place: Place?
    /// Hourly readings, oldest first.
    var history: HistoricalPollutants = []
    var historyFetchedAt: Date?
    /// The station's 空品區 only, every day from the fetch on; past days are
    /// dropped when shown.
    var forecast: [AqiForecast] = []
    var forecastFetchedAt: Date?
    var cam: Cam?
    /// When the manifest last named `cam`, or, while its new frame fails to
    /// download, when the saved frame was.
    var camFetchedAt: Date?

    /// "Taipei City" / "臺北市", in the reader's language.
    var displayCounty: String? {
        Self.preferred(chinese: Locale.isChinese, local: place?.countyLocal, english: place?.county)
    }

    /// "North" / "北部空品區", in the reader's language.
    var displayArea: String? {
        Self.preferred(chinese: Locale.isChinese, local: place?.areaLocal, english: place?.area)
    }

    /// Today's and tomorrow's forecast, or nil when there is none to show.
    func areaForecast(today: String = AqiForecastDates.today()) -> AreaForecast? {
        AqiForecastMatcher.forecast(
            areaLocal: place?.areaLocal, countyLocal: place?.countyLocal, in: forecast,
            title: displayArea, today: today, limit: 2
        )
    }

    private static func preferred(chinese: Bool, local: String?, english: String?) -> String? {
        let first = chinese ? local : english
        let second = chinese ? english : local
        return [first, second].compactMap { $0 }.first { !$0.isEmpty }
    }
}

extension WidgetStationDetail.Place {
    init(_ pollutant: Pollutant) {
        self.init(
            nameLocal: pollutant.nameLocal, lat: pollutant.lat, lon: pollutant.lon,
            county: pollutant.county, countyLocal: pollutant.countyLocal,
            area: pollutant.area, areaLocal: pollutant.areaLocal
        )
    }
}

extension WidgetStationDetail {
    /// The detail after one refresh. A `nil` input is a failed fetch and
    /// keeps what `previous` had; a fetch that worked replaces it.
    ///
    /// - Parameters:
    ///   - previous: the cached detail; ignored when it is another station's,
    ///     and each part of it a week past its fetch is dropped.
    ///   - place: from this refresh's current-pollutants response.
    ///   - history: hourly readings, oldest first. Empty counts as failed.
    ///   - forecasts: every area's rows from `twaqi_aqi_forecast`. Empty
    ///     counts as failed, as in `AqiForecastStore`.
    ///   - cams: the cam manifest. A station with no cam in a manifest that
    ///     loaded has its cam dropped.
    ///   - today: Taiwan's calendar day, `YYYY-MM-DD`.
    ///   - now: when this refresh ran; a part fetched now is dated with it.
    static func merged(
        previous: WidgetStationDetail?,
        stationId: Int,
        place: Place?,
        history: HistoricalPollutants?,
        forecasts: [AqiForecast]?,
        cams: [StationCam]?,
        today: String,
        now: Date = Date()
    ) -> WidgetStationDetail {
        let previous = previous?.stationId == stationId ? previous?.droppingExpired(now: now) : nil
        // Starts as the previous copy: a part that fails to fetch keeps it,
        // with its old date.
        var detail = previous ?? WidgetStationDetail(stationId: stationId)
        if let place = place {
            detail.place = place
        }

        if let history = history, !history.isEmpty {
            detail.history = history
            detail.historyFetchedAt = now
        }

        if let forecasts = forecasts, !forecasts.isEmpty, let place = detail.place {
            let areas = Array(Set(forecasts.filter { $0.forecastDate >= today }.map(\.area))).sorted()
            detail.forecast = AqiForecastMatcher
                .area(areaLocal: place.areaLocal, countyLocal: place.countyLocal, in: areas)
                .map { AqiForecastMatcher.days(area: $0, in: forecasts, today: today) } ?? []
            detail.forecastFetchedAt = now
        }

        if let cams = cams, let place = detail.place {
            // Matched by the Chinese name and position, as the station page does.
            detail.cam = StationCamMatcher.match(name: place.nameLocal, lat: place.lat, lon: place.lon, in: cams)
                .map { Cam(siteId: $0.siteId, time: $0.time) }
            detail.camFetchedAt = detail.cam == nil ? nil : now
        }
        return detail
    }

    /// This detail without the parts fetched more than `WatchStore.maxReadingAge`
    /// ago (or never). Saving the file again on every refresh doesn't keep a
    /// part that keeps failing alive.
    func droppingExpired(now: Date = Date()) -> WidgetStationDetail {
        func isExpired(_ date: Date?) -> Bool {
            guard let date = date else { return true }
            return now.timeIntervalSince(date) > WatchStore.maxReadingAge
        }
        var detail = self
        if isExpired(historyFetchedAt) {
            detail.history = []
            detail.historyFetchedAt = nil
        }
        if isExpired(forecastFetchedAt) {
            detail.forecast = []
            detail.forecastFetchedAt = nil
        }
        if isExpired(camFetchedAt) {
            detail.cam = nil
            detail.camFetchedAt = nil
        }
        return detail
    }

    /// What to do about the cam frame once `merged` has picked the cam.
    enum CamFrameAction: Equatable {
        /// No cam: the saved frame, if any, goes.
        case remove
        /// The saved frame is this capture already.
        case keep
        /// Download the frame for this cam.
        case fetch
    }

    static func camFrameAction(previous: Cam?, current: Cam?, hasSavedFrame: Bool) -> CamFrameAction {
        guard let current = current else { return .remove }
        return current == previous && hasSavedFrame ? .keep : .fetch
    }

    /// The cam after a frame download. A 404 means the cam has no frame: the
    /// section is left out. Any other failure keeps the previous frame of the
    /// same cam when there is one, else leaves the section out.
    static func camAfterDownload(previous: Cam?, current: Cam, status: Int?, hasSavedFrame: Bool) -> Cam? {
        if status == 200 { return current }
        if status == 404 { return nil }
        guard hasSavedFrame, let previous = previous, previous.siteId == current.siteId else { return nil }
        return previous
    }
}

/// The extra-large widget's last good detail per station, and its cam frame,
/// in the app group container so the purge at app launch reaches it
/// (`OfflineCacheRetention.purge(directory:widgetDirectory:)`).
struct WidgetStationDetailCache {
    static let directoryName = "WidgetStationDetail"

    let directory: URL

    /// Nil without the app group (it is always there in the shipped targets).
    static var shared: WidgetStationDetailCache? {
        defaultDirectory.map(WidgetStationDetailCache.init(directory:))
    }

    static var defaultDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WatchStore.appGroup)?
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    func detailFile(stationId: Int) -> URL {
        directory.appendingPathComponent("\(stationId).json")
    }

    func frameFile(stationId: Int) -> URL {
        directory.appendingPathComponent("\(stationId).jpg")
    }

    /// The saved detail, unless it was written more than
    /// `WatchStore.maxReadingAge` ago (the same week as every offline cache),
    /// without its parts fetched longer ago than that.
    func detail(stationId: Int, now: Date = Date()) -> WidgetStationDetail? {
        let file = detailFile(stationId: stationId)
        guard let modified = Self.modificationDate(of: file),
              now.timeIntervalSince(modified) <= WatchStore.maxReadingAge,
              let data = try? Data(contentsOf: file),
              let detail = try? JSONDecoder().decode(WidgetStationDetail.self, from: data)
        else { return nil }
        return detail.droppingExpired(now: now)
    }

    func save(_ detail: WidgetStationDetail) {
        guard let data = try? JSONEncoder().encode(detail) else { return }
        createDirectory()
        try? data.write(to: detailFile(stationId: detail.stationId), options: .atomic)
    }

    func hasFrame(stationId: Int) -> Bool {
        FileManager.default.fileExists(atPath: frameFile(stationId: stationId).path)
    }

    func saveFrame(_ data: Data, stationId: Int) {
        createDirectory()
        try? data.write(to: frameFile(stationId: stationId), options: .atomic)
    }

    func removeFrame(stationId: Int) {
        try? FileManager.default.removeItem(at: frameFile(stationId: stationId))
    }

    private func createDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func modificationDate(of file: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }
}
