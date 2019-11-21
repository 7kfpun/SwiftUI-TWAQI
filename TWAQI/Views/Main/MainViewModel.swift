//
//  MainViewModel.swift
//  TWAQI
//
//  Created by kf on 2/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation
import SwiftDate

class MainViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    @Published var isLoading: Bool = true {
        willSet {
            self.objectWillChange.send()
        }
    }

    var isShowCustomAd: Bool = false
    var customAd: CustomAd?

    private(set) lazy var getData: () -> Void = {
        APIManager.getCustomAd { result in
            switch result {
            case .success(let customAd):
                self.customAd = customAd
                self.isShowCustomAd = customAd.impressionRate > Double.random(in: 0 ..< 1)
                self.isLoading = false

                if self.isShowCustomAd {
                    var components = URLComponents(string: customAd.imageUrl)!
                    components.query = nil

                    TrackingManager.logEvent(eventName: "ad_custom_\(customAd.name)_impression", parameters: [
                        "name": customAd.name,
                        "impressionRate": customAd.impressionRate,
                        "imageUrl": "\(components.url!)",
                        "destinationUrl": customAd.destinationUrl,
                    ])
                }

            case .failure(let error):
                print(error.localizedDescription)
                self.isLoading = false
            }
        }
    }

    private(set) lazy var loadOneSignalSettings: () -> Void = {
        OneSignalManager.getOneSignalSettings { result in
            switch result {
            case .success(let result):
                print(result)
                let settings = SettingsStore()
                if let isForecastEnabled = result.isForecastEnabled, isForecastEnabled != settings.isForecastEnabled {
                    settings.isForecastEnabled = isForecastEnabled
                }

                if let isDndEnabled = result.isDndEnabled, isDndEnabled != settings.isDndEnabled {
                    settings.isDndEnabled = isDndEnabled
                }

                if let dndStartTime = result.dndStartTime {
                    var components = DateComponents()
                    components.hour = Int(dndStartTime / 60)
                    components.minute = dndStartTime % 60
                    settings.dndStartTime = NSCalendar.current.date(from: components) ?? Date()
                }

                if let dndEndTime = result.dndEndTime {
                    var components = DateComponents()
                    components.hour = Int(dndEndTime / 60)
                    components.minute = dndEndTime % 60
                    settings.dndEndTime = NSCalendar.current.date(from: components) ?? Date() + 2.hours
                }

            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }
}
