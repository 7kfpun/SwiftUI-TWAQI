//
//  FavouriteListViewModel.swift
//  TWAQI
//
//  Created by kf on 4/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class FavouriteListViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    let settings = SettingsStore()

    @Published var favouritePollutants: NewPollutants = [] {
        willSet { self.objectWillChange.send() }
    }

//    func getFavouritePollutants() {
//        let stationIds = (self.stationSettings.keys.map {
//            TaiwanStationMapper().toStationId(name: String($0)) != "" ? TaiwanStationMapper().toStationId(name: String($0)) : String($0)
//        }).joined(separator: ",")
//        print("getFavouritePollutants", stationIds)
//
//        if !stationIds.isEmpty {
//            APIManager.getCurrentPollutantsByStationId(stationId: stationIds) { result in
//                switch result {
//                case .success(let result):
//                    print("getCurrentPollutantsByStationId Total: \(result.count)")
//                    self.favouritePollutants = result
//                case .failure(let error):
//                    print(error.localizedDescription)
//                }
//            }
//        } else {
//            self.favouritePollutants = []
//        }
//    }

    private(set) lazy var getData: () -> Void = {
        let stationIds = (self.settings.savedFavouriteStations.map { String($0) }).joined(separator: ",")
        print("getFavouritePollutants", stationIds)

        if !stationIds.isEmpty {
            APIManager.getCurrentPollutantsByStationId(stationId: stationIds) { result in
                switch result {
                case .success(let result):
                    print("getCurrentPollutantsByStationId Total: \(result.count)")
                    self.favouritePollutants = result
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
        } else {
            self.favouritePollutants = []
        }
    }
}
