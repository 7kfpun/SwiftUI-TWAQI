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

    @Published var historyPollutants: [HistoryPollutant] = [] {
        willSet { self.objectWillChange.send() }
    }

    @Published var isLoading: Bool = false {
        willSet { self.objectWillChange.send() }
    }

    init(station: Station, historyPollutants: [HistoryPollutant] = []) {
        self.station = station
        self.historyPollutants = historyPollutants
    }

    private(set) lazy var getData: () -> Void = {
        guard let nameLocal = self.station?.nameLocal else {
            return
        }

        self.isLoading = true
        HistoryPollutantManager.getHistory(nameLocal: nameLocal) { result in
            switch result {
            case .success(let historyPollutants):
                self.historyPollutants = historyPollutants
            case .failure(let error):
                print(error.localizedDescription)
            }
            self.isLoading = false
        }
    }
}
