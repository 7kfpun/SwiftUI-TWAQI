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

    @Published var forecastDetail: String = "" {
        willSet { self.objectWillChange.send() }
    }

    @Published var forecastAreas: [ForecastArea] = [] {
        willSet { self.objectWillChange.send() }
    }

    init(forecastDetail: String = "", forecastAreas: [ForecastArea] = []) {
        self.forecastDetail = forecastDetail
        self.forecastAreas = forecastAreas
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
}
