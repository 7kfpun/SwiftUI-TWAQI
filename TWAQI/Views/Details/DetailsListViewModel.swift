//
//  DetailsListViewModel.swift
//  TWAQI
//
//  Created by kf on 3/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class DetailsListViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    @Published var stations: Stations = [] {
        willSet { self.objectWillChange.send() }
    }

    private(set) lazy var getData: () -> Void = {
        let settings = SettingsStore()
        let countryCode = settings.closestCountryCode
        APIManager.getStations(countryCode: countryCode) { result in
            switch result {
            case .success(let stations):
                self.stations = stations
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }
}
