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
    let objectWillChange = ObservableObjectPublisher()
    let settings = SettingsStore()

    var stationId: Int

    @Published var station: Station? {
        willSet { self.objectWillChange.send() }
    }

    @Published var historyPollutants: HistoricalPollutants = [] {
        willSet { self.objectWillChange.send() }
    }

    @Published var isFavourited: Bool = false {
        willSet { self.objectWillChange.send() }
    }

    init(stationId: Int, historyPollutants: HistoricalPollutants = []) {
        self.stationId = stationId
        self.historyPollutants = historyPollutants
        self.isFavourited = settings.savedFavouriteStations.contains(stationId)
    }

    private(set) lazy var getData: () -> Void = {
        APIManager.getHistoricalPollutants(stationId: self.stationId) { result in
            switch result {
            case .success(let result):
                self.station = result["station"] as? Station
                self.historyPollutants = result["data"] as! HistoricalPollutants
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
        TrackingManager.logEvent(eventName: "save_favourite_station", parameters: [
            "label": self.isFavourited ? "on" : "off",
            "stationId": self.stationId,
        ])
    }
}
