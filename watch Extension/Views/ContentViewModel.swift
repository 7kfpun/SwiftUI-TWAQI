//
//  ContentViewModel.swift
//  watch Extension
//
//  Created by kf on 18/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class ContentViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var station: Station?

    @Published var historicalPollutants: HistoricalPollutants = [] {
        willSet { self.objectWillChange.send() }
    }

    @Published var isLoading: Bool = false {
        willSet { self.objectWillChange.send() }
    }

    init(station: Station, historicalPollutants: HistoricalPollutants = []) {
        self.station = station
        self.historicalPollutants = historicalPollutants
    }

    private(set) lazy var getData: () -> Void = {
        if let station = self.station {
            self.isLoading = true
            APIManager.getHistoricalPollutants(stationId: station.id) { result in
                switch result {
                case .success(let result):
                    self.station = result["station"] as? Station
                    self.historicalPollutants = result["data"] as! HistoricalPollutants
                case .failure(let error):
                    print(error.localizedDescription)
                }
                self.isLoading = false
            }
        }
    }
}
