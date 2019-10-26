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
    var station: Station

    @Published var historyPollutants: [HistoryPollutant] = [] {
        willSet { self.objectWillChange.send() }
    }

    init(station: Station, historyPollutants: [HistoryPollutant] = []) {
        self.station = station
        self.historyPollutants = historyPollutants
    }

    private(set) lazy var getData: () -> Void = {
        APIManager.getHistory(nameLocal: self.station.nameLocal) { result in
            switch result {
            case .success(let historyPollutants):
                self.historyPollutants = historyPollutants
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }
}
