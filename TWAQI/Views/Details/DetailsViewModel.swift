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

    @Published var isFavourited: Bool = false

    /// `pollutant` is the last good reading saved, because the latest
    /// request failed.
    @Published var isShowingLastGood = false

    /// Both requests failed and there was no saved reading to show instead.
    @Published var loadFailed = false

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

    init(stationId: Int, historicalPollutants: HistoricalPollutants = []) {
        self.stationId = stationId
        self.historicalPollutants = historicalPollutants
        self.isFavourited = settings.savedFavouriteStations.contains(stationId)
    }

    private(set) lazy var getData: () -> Void = {
        // The last good reading at once, so a station opened offline — or
        // on a slow connection — is not a blank page. The request replaces it.
        if self.pollutant == nil, let saved = PollutantCache.shared.pollutant(stationId: self.stationId) {
            self.pollutant = saved
            self.findCam(name: saved.nameLocal, lat: saved.lat, lon: saved.lon)
            self.findForecast(areaLocal: saved.areaLocal, countyLocal: saved.countyLocal, title: saved.displayArea)
        }
        self.generation += 1
        let generation = self.generation
        self.answers = []
        self.loadFailed = false

        APIManager.getHistoricalPollutants(stationId: self.stationId) { result in
            switch result {
            case .success(let result):
                self.station = result["station"] as? Station
                self.historicalPollutants = result["data"] as? HistoricalPollutants ?? []
                if let station = self.station {
                    self.findCam(name: station.nameLocal, lat: station.lat, lon: station.lon)
                    self.findForecast(areaLocal: station.areaLocal, countyLocal: station.countyLocal, title: station.displayArea)
                }
                self.requestFinished(failed: false, generation: generation)
            case .failure(let error):
                print(error.localizedDescription)
                self.requestFinished(failed: true, generation: generation)
            }
        }

        APIManager.getCurrentPollutantsByStationId(stationId: "\(self.stationId)") { result in
            switch result {
            case .success(let pollutants):
                // An empty answer keeps a saved reading rather than blanking it.
                if let pollutant = pollutants.first {
                    self.pollutant = pollutant
                    self.isShowingLastGood = false
                    self.findCam(name: pollutant.nameLocal, lat: pollutant.lat, lon: pollutant.lon)
                    self.findForecast(areaLocal: pollutant.areaLocal, countyLocal: pollutant.countyLocal, title: pollutant.displayArea)
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

    private(set) lazy var favouriteStationToggle: () -> Void = {
        self.isFavourited.toggle()
        if self.isFavourited {
            self.settings.savedFavouriteStations.append(self.stationId)
        } else {
            self.settings.savedFavouriteStations = self.settings.savedFavouriteStations.filter { $0 != self.stationId }
        }
        TrackingManager.logEvent(eventName: "favourite_station_saved", parameters: [
            "label": self.isFavourited ? "on" : "off",
            "stationId": self.stationId,
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

    /// Most recent reading, preferring live current conditions over history.
    var latestPublishTime: String? {
        pollutant?.publishTime ?? historicalPollutants.last?.publishTime
    }
}
