//
//  ForecastViewModel.swift
//  TWAQI
//
//  Created by kf on 12/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class ForecastViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    let settings = SettingsStore()

    @Published var forecastDetail: String = "" {
        willSet { self.objectWillChange.send() }
    }

    @Published var forecastAreas: [ForecastArea] = [] {
        willSet { self.objectWillChange.send() }
    }

    @Published var isForecastEnabled: Bool {
        willSet(newValue) {
            self.objectWillChange.send()

            if newValue {
                OneSignalManager.enableForecast { result in
                    switch result {
                    case .success(let result):
                        print(result)
                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                }
            } else {
                OneSignalManager.disableForecast { result in
                    switch result {
                    case .success(let result):
                        print(result)
                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                }
            }
            settings.isForecastEnabled = newValue

            TrackingManager.logEvent(eventName: "set_forecast_notification", parameters: ["label": newValue ? "on" : "off"])
        }
    }

    init(forecastDetail: String = "", forecastAreas: [ForecastArea] = []) {
        self.forecastDetail = forecastDetail
        self.forecastAreas = forecastAreas
        self.isForecastEnabled = settings.isForecastEnabled
    }

    private(set) lazy var getData: () -> Void = {
        APIManager.getForecast { result in
            switch result {
            case .success(let forecastAreas):
                if !forecastAreas.isEmpty {
                    self.forecastAreas = forecastAreas
                    self.forecastDetail = forecastAreas[0].content
                }
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }

    @Published var isCustomAdLoading: Bool = true {
        willSet {
            self.objectWillChange.send()
        }
    }

    var isShowCustomAd: Bool = false
    var customAd: CustomAd?

    private(set) lazy var getCustomAd: () -> Void = {
        APIManager.getCustomAd(position: "forecast") { result in
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
