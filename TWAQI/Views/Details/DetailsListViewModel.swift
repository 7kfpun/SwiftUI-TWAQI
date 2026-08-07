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

    @Published var isCustomAdLoading: Bool = true

    var isShowCustomAd: Bool = false
    var customAd: CustomAd?

    private(set) lazy var getCustomAd: () -> Void = {
        APIManager.getCustomAd(position: "detailslist") { result in
            switch result {
            case .success(let customAd):
                self.customAd = customAd
                self.isShowCustomAd = true
            case .failure(let error):
                print(error.localizedDescription)
                self.isShowCustomAd = false
            }

            self.isCustomAdLoading = false
        }
    }
}
