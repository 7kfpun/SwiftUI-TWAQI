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

    @Published var station: NewStation? {
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
        APIManager.getHourlyHistorical(stationId: self.stationId) { result in
            switch result {
            case .success(let result):
                self.station = result["station"] as? NewStation
                self.historyPollutants = result["data"] as! HistoricalPollutants
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }

    private(set) lazy var favouriteStationToggle: () -> Void = {
        if self.isFavourited {
            self.settings.savedFavouriteStations = self.settings.savedFavouriteStations.filter { $0 != self.stationId }
        } else {
            self.settings.savedFavouriteStations.append(self.stationId)
        }
        self.isFavourited.toggle()
        print("settings.savedFavouriteStations", self.settings.savedFavouriteStations)
    }
}
