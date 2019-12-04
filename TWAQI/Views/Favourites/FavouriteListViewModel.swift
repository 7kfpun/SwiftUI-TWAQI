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
        let stationIds = (self.stationSettings.keys.map { String($0) }).joined(separator: ",")
        print("getFavouritePollutants", stationIds)

        APIManager.getCurrentPollutantsByStationIds(stationIds: stationIds) { result in
            switch result {
            case .success(let result):
                print("getCurrentPollutantsByStationIds Total: \(result.count)")
                self.favouritePollutants = result
            case .failure(let error):
                print(error.localizedDescription)
            }
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
