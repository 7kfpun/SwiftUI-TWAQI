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
    
    @Published var isDisabled: Bool = true {
        willSet { self.objectWillChange.send() }
    }

    init(station: Station) {
        self.station = station

        var notificationTagCode: String
        if station.countryCode == "twn" {
            notificationTagCode = station.name
        } else {
            notificationTagCode = "\(station.id)"
        }

        self.stationSetting = OneSignalStationSetting(
            stationName: notificationTagCode,
            isPollutionNotificationEnabled: false,
            isCleanlinessNotificationEnabled: false
        )

        OneSignalManager.getOneSignalSettings { result in
            switch result {
            case .success(let result):
                print("OneSignalManager.getOneSignalSettings", result)
                self.isDisabled = result.stationSettings.count >= 2
                if let resultStationSetting = result.stationSettings[notificationTagCode] {
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
