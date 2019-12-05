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

    var stationSettings: [String: OneSignalStationSetting] = [:] {
       didSet {
           getFavouritePollutants()
       }
   }

    @Published var favouritePollutants: NewPollutants = [] {
        willSet { self.objectWillChange.send() }
    }

    func getFavouritePollutants() {
        let stationIds = (self.stationSettings.keys.map {
            TaiwanStationMapper().toStationId(name: String($0)) != "" ? TaiwanStationMapper().toStationId(name: String($0)) : String($0)
        }).joined(separator: ",")
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

    private(set) lazy var getData: () -> Void = {
        OneSignalManager.getOneSignalSettings { result in
            switch result {
            case .success(let result):
                print("OneSignalManager.getOneSignalSettings", result)
                self.stationSettings = result.stationSettings
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }
}
