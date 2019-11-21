//
//  MainViewModel.swift
//  TWAQI
//
//  Created by kf on 2/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

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
}
