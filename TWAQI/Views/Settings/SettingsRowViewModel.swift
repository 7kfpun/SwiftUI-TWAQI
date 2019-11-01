//
//  SettingsRowViewModel.swift
//  TWAQI
//
//  Created by kf on 30/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class SettingsRowViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var station: Station

    init(station: Station) {
        self.station = station
        self.stationSetting = OneSignalStationSetting(stationName: station.name, isPollutionNotificationEnabled: false, isCleanlinessNotificationEnabled: false)

        OneSignalManager.getOneSignalSettings { result in
            switch result {
            case .success(let result):
                print(result)
                if let resultStationSetting = result.stationSettings[station.name] {
                    self.stationSetting = resultStationSetting
                }
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }

    @Published var stationSetting: OneSignalStationSetting {
        willSet(newStationSetting) {
            print(newStationSetting)
            OneSignalManager.sendTags(
                tags: newStationSetting.getTags()
            ) { result in
                switch result {
                case .success(let result):
                    print(result)
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
            self.objectWillChange.send()
        }
    }
}
