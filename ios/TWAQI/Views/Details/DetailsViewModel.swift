//
//  DetailsViewModel.swift
//  TWAQI
//
//  Created by kf on 13/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class DetailsViewModel: ObservableObject {
    let settings = SettingsStore()

    var stationId: Int

    @Published var station: Station?

    /// Current conditions for this station. Carries the location detail
    /// (address, area, county, station type) and wind that the historical
    /// endpoint does not return.
    @Published var pollutant: Pollutant?

    @Published var historicalPollutants: HistoricalPollutants = []

    /// Whether the station has an alert on.
    @Published private(set) var hasAlerts: Bool

    /// Unfavouriting waits on the reader: it would also turn alerts off.
    @Published var isConfirmingUnfavourite = false

    /// Why favouriting just now left the station's alerts off, when the
    /// reader can do something about it. Nil otherwise.
    @Published var favouriteAlertsHint: FavouriteAlertsHint?

    /// The station record didn't load, so there is no alerts card to show:
    /// the page shows why instead.
    @Published var stationLoadFailed = false

    private var alertsObserver: NSObjectProtocol?

    /// `pollutant` is the last good reading saved, because the latest
    /// request failed.
    @Published var isShowingLastGood = false

    /// Both requests failed and there was no saved reading to show instead.
    @Published var loadFailed = false

    /// The API answered, and has no current reading for this station. Search
    /// lists every station `getStations` knows (~150), but only the ones still
    /// reporting (~84, the map's) have one; the rest are retired or offline
    /// sites whose history can be years old. Not an outage — `loadFailed` and
    /// `isShowingLastGood` cover those.
    @Published var isNotReporting = false

    /// Answers from the latest `getData`, so `loadFailed` is decided once
    /// both requests have answered. `onAppear` can fire again while the first
    /// pair is still on the wire; answers from an older pair are not counted.
    private var generation = 0
    private var answers: [Bool] = []

    /// This station's MOENV webcam, found by joining on name and position.
    @Published var cam: StationCamState = .loading

    /// MOENV's forecast for this station's 空品區, today onwards. Nil until
    /// loaded, and stays nil when there is none (offline, no match) — the
    /// screen then shows no forecast section at all.
    @Published var forecast: AreaForecast?

    /// CWA weather near this station (FOX-11): the nearest CWA station's
    /// reading and the county forecast. Nil until loaded, and stays nil when
    /// there is nothing in range — the screen then shows no weather card.
    @Published var weather: StationWeather?

    /// The station's county in the app's language, for the weather card's
    /// heading.
    @Published var weatherCountyTitle: String?

    /// `pollutant` seeds a reading the caller already holds, so the heart
    /// works before the first load answers.
    init(stationId: Int, historicalPollutants: HistoricalPollutants = [], pollutant: Pollutant? = nil) {
        self.stationId = stationId
        self.pollutant = pollutant
        self.historicalPollutants = historicalPollutants
        self.hasAlerts = FavouriteAlerts.isOn(stationId: stationId)
        self.alertsObserver = NotificationCenter.default.addObserver(
            forName: FavouriteAlerts.changed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let isOn = FavouriteAlerts.isOn(in: notification, stationId: self.stationId) else { return }
            if self.hasAlerts != isOn {
                self.hasAlerts = isOn
            }
        }
    }

    deinit {
        alertsObserver.map(NotificationCenter.default.removeObserver)
    }

    private(set) lazy var getData: () -> Void = {
        // The last good reading at once, so a station opened offline — or
        // on a slow connection — is not a blank page. The request replaces it.
        if self.pollutant == nil, let saved = PollutantCache.shared.pollutant(stationId: self.stationId) {
            self.pollutant = saved
            self.findCam(name: saved.nameLocal, lat: saved.lat, lon: saved.lon)
            self.findForecast(areaLocal: saved.areaLocal, countyLocal: saved.countyLocal, title: saved.displayArea)
            self.findWeather(lat: saved.lat, lon: saved.lon, county: saved.county, countyLocal: saved.countyLocal)
        }
        self.generation += 1
        let generation = self.generation
        self.answers = []
        self.loadFailed = false

        APIManager.getHistoricalPollutants(stationId: self.stationId) { result in
            // An answer from an older pair while the latest is still on the
            // wire says nothing about whether the record will load.
            let isLatest = generation == self.generation
            switch result {
            case .success(let result):
                // An older answer without the record doesn't take away one
                // already loaded.
                let station = result["station"] as? Station
                if station != nil || isLatest {
                    self.station = station
                }
                if self.station != nil || isLatest {
                    self.stationLoadFailed = self.station == nil
                }
                self.historicalPollutants = result["data"] as? HistoricalPollutants ?? []
                if let station = self.station {
                    self.findCam(name: station.nameLocal, lat: station.lat, lon: station.lon)
                    self.findForecast(areaLocal: station.areaLocal, countyLocal: station.countyLocal, title: station.displayArea)
                    self.findWeather(lat: station.lat, lon: station.lon, county: station.county, countyLocal: station.countyLocal)
                }
                self.requestFinished(failed: false, generation: generation)
            case .failure(let error):
                print(error.localizedDescription)
                if isLatest {
                    self.stationLoadFailed = self.station == nil
                }
                self.requestFinished(failed: true, generation: generation)
            }
        }

        APIManager.getCurrentPollutantsByStationId(stationId: "\(self.stationId)") { result in
            switch result {
            case .success(let pollutants):
                // An empty answer keeps a saved reading rather than blanking
                // it, but is still the API saying it has no current reading:
                // the page says so, and the saved one shows its own age.
                if let pollutant = pollutants.first {
                    self.pollutant = pollutant
                    self.isShowingLastGood = false
                    self.isNotReporting = false
                    self.findCam(name: pollutant.nameLocal, lat: pollutant.lat, lon: pollutant.lon)
                    self.findForecast(areaLocal: pollutant.areaLocal, countyLocal: pollutant.countyLocal, title: pollutant.displayArea)
                    self.findWeather(lat: pollutant.lat, lon: pollutant.lon, county: pollutant.county, countyLocal: pollutant.countyLocal)
                } else {
                    self.isNotReporting = true
                    // Online, so whatever is on screen is not an offline fallback.
                    self.isShowingLastGood = false
                }
                self.requestFinished(failed: false, generation: generation)
            case .failure(let error):
                print(error.localizedDescription)
                // Whatever is on screen — the saved reading, or one from
                // earlier this visit — is now the last good one.
                self.isShowingLastGood = self.pollutant != nil
                self.requestFinished(failed: true, generation: generation)
            }
        }
    }

    private func requestFinished(failed: Bool, generation: Int) {
        guard generation == self.generation else { return }
        answers.append(failed)
        guard answers.count == 2 else { return }
        loadFailed = answers.allSatisfy { $0 } && pollutant == nil && historicalPollutants.isEmpty
    }

    /// Read from the shared defaults rather than kept here, so the heart
    /// follows changes made in Favourites or by switching an alert on.
    var isFavourited: Bool {
        settings.savedFavouriteStations.contains(stationId)
    }

    /// Whether this id is a station at all: its record or a reading loaded,
    /// now or from the cache. Until then the heart can't add it, so a page
    /// opened for an unknown id (a stale or made-up link) never puts that id
    /// in Favourites, the widget or Siri's list (FOX-74). Removing one already
    /// there is always allowed.
    var canAddFavourite: Bool {
        station != nil || pollutant != nil
    }

    func favouriteStationToggle() {
        if !isFavourited {
            guard canAddFavourite else { return }
            settings.savedFavouriteStations.append(stationId)
            logFavourite(on: true)
            enableAlertsForNewFavourite()
        } else if hasAlerts {
            isConfirmingUnfavourite = true
        } else {
            removeFromFavourites()
        }
    }

    /// Takes the station out of Favourites, and turns its alerts off with it
    /// when it has any — only after `isConfirmingUnfavourite` was answered.
    func removeFromFavourites() {
        FavouriteAlerts.clear(stationId: stationId)
        settings.savedFavouriteStations.removeAll { $0 == stationId }
        logFavourite(on: false)
    }

    /// A new favourite gets alerts, so favouriting is the one step to being
    /// told when the air turns (FOX-31). The favourite stands whatever
    /// happens here; at the station cap or with notifications off the
    /// reader is told why the alerts stayed off.
    private func enableAlertsForNewFavourite() {
        let stationId = stationId
        var siteId: String?
        if case .available(let cam) = cam {
            siteId = cam.siteId
        }

        FavouriteAlerts.enableForNewFavourite(
            stationId: stationId,
            siteId: siteId,
            isStillFavourite: { [weak self] in self?.isFavourited ?? false }
        ) { [weak self] outcome in
            guard let self = self else { return }
            switch outcome {
            case .capReached:
                self.favouriteAlertsHint = .capReached
            case .notificationsDenied:
                self.favouriteAlertsHint = .notificationsDenied
            case .enabled, .alreadyOn, .notChanged:
                // `.notChanged`: unfavourited meanwhile, which needs no word.
                break
            }
        }
    }

    private func logFavourite(on: Bool) {
        TrackingManager.logEvent(.favouriteStationSaved, parameters: [
            "label": on ? "on" : "off",
            "stationId": stationId,
        ])
    }

    /// Called by both station requests — each carries the Chinese name and
    /// coordinates the join needs. The first to find a cam wins; a miss leaves
    /// the other free to try with its copy of the name.
    ///
    /// The AQI `station_id` is never used here: it is a different numbering
    /// from MOENV's SiteId, which is what the cam URLs are keyed by.
    private func findCam(name: String, lat: Double, lon: Double) {
        if case .available = cam { return }

        StationCamStore.shared.cams { cams in
            if let cam = StationCamMatcher.match(name: name, lat: lat, lon: lon, in: cams) {
                self.cam = .available(cam)
            } else if self.cam == .loading {
                self.cam = .missing
            }
        }
    }

    /// Called by both station requests, like `findCam`; the first match wins.
    private func findForecast(areaLocal: String?, countyLocal: String?, title: String?) {
        guard forecast == nil, areaLocal != nil || countyLocal != nil else { return }

        AqiForecastStore.shared.forecasts { forecasts in
            guard self.forecast == nil else { return }
            self.forecast = AqiForecastMatcher.forecast(
                areaLocal: areaLocal,
                countyLocal: countyLocal,
                in: forecasts,
                title: title
            )
        }
    }

    /// Called by both station requests, like `findCam`; the first match wins.
    /// The join is by position and county name: CWA station ids are a
    /// numbering of their own.
    private func findWeather(lat: Double, lon: Double, county: String?, countyLocal: String?) {
        guard weather == nil else { return }

        StationWeatherStore.shared.weather { file in
            guard self.weather == nil, let file = file else { return }
            guard let weather = StationWeatherMatcher.weather(lat: lat, lon: lon, countyLocal: countyLocal, in: file) else { return }
            self.weatherCountyTitle = Locale.isChinese ? countyLocal : county
            self.weather = weather
        }
    }

    /// The newest history point is from the last day, so the 24-hour chart is
    /// still about today. A station that stopped reporting long ago still
    /// returns its last 24 points, which would read as a current trend.
    var hasRecentHistory: Bool {
        guard
            let publishTime = historicalPollutants.last?.publishTime,
            let date = Date.fromApi(publishTime)
        else { return false }
        return Date().timeIntervalSince(date) < 24 * 60 * 60
    }

    /// Most recent reading, preferring live current conditions over history.
    var latestPublishTime: String? {
        pollutant?.publishTime ?? historicalPollutants.last?.publishTime
    }
}

/// Why favouriting just now left the station's alerts off, as told to the
/// reader.
enum FavouriteAlertsHint: Equatable {
    /// `FavouriteAlerts.maxAlertedStations` other stations already have alerts on.
    case capReached
    /// Notifications are turned off for the app in Settings.
    case notificationsDenied
}
