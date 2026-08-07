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

    @Published var stations: Stations = []

    private(set) lazy var getData: () -> Void = {
        let settings = SettingsStore()
        // Scoped to the supported country: those are the only stations whose
        // detail screen and notifications work.
        let countryCode = settings.supportedCountryCode.isEmpty
            ? settings.closestCountryCode
            : settings.supportedCountryCode
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
