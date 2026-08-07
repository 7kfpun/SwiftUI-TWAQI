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
            case .failure(let error):
                print(error.localizedDescription)
            }
        }

        APIManager.getCurrentPollutantsByStationId(stationId: "\(self.stationId)") { result in
            switch result {
            case .success(let pollutants):
                self.pollutant = pollutants.first
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

    /// Most recent reading, preferring live current conditions over history.
    var latestPublishTime: String? {
        pollutant?.publishTime ?? historicalPollutants.last?.publishTime
    }
}
