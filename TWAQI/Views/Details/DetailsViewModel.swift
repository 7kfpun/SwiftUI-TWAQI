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

    /// This station's MOENV webcam, found by joining on name and position.
    @Published var cam: StationCamState = .loading

    init(stationId: Int, historicalPollutants: HistoricalPollutants = []) {
        self.stationId = stationId
        self.historicalPollutants = historicalPollutants
        self.isFavourited = settings.savedFavouriteStations.contains(stationId)
    }

    private(set) lazy var getData: () -> Void = {
        APIManager.getHistoricalPollutants(stationId: self.stationId) { result in
            switch result {
            case .success(let result):
                self.station = result["station"] as? Station
                self.historicalPollutants = result["data"] as? HistoricalPollutants ?? []
                if let station = self.station {
                    self.findCam(name: station.nameLocal, lat: station.lat, lon: station.lon)
                }
            case .failure(let error):
                print(error.localizedDescription)
            }
        }

        APIManager.getCurrentPollutantsByStationId(stationId: "\(self.stationId)") { result in
            switch result {
            case .success(let pollutants):
                self.pollutant = pollutants.first
                if let pollutant = self.pollutant {
                    self.findCam(name: pollutant.nameLocal, lat: pollutant.lat, lon: pollutant.lon)
                }
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
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

    /// Most recent reading, preferring live current conditions over history.
    var latestPublishTime: String? {
        pollutant?.publishTime ?? historicalPollutants.last?.publishTime
    }
}
