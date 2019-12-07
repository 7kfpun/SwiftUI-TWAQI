//
//  StationListViewModel.swift
//  watch Extension
//
//  Created by kf on 7/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class StationListViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    var country: Country

    @Published var stations: Stations = [] {
        willSet { self.objectWillChange.send() }
    }

    init(country: Country) {
        self.country = country
    }

    private(set) lazy var getData: () -> Void = {
        APIManager.getStations(countryCode: self.country.code) { result in
            switch result {
            case .success(let stations):
                self.stations = stations
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }
}
