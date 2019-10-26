//
//  ForecastViewModel.swift
//  TWAQI
//
//  Created by kf on 12/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Alamofire
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
        let url: String = getEnv("FORECAST API")!
        AF.request(url)
            .validate(contentType: ["application/json"])
            .responseData { response in
                do {
                    debugPrint(response)

                    let forecastAreas = try JSONDecoder().decode([ForecastArea].self, from: response.data!)

                    if !forecastAreas.isEmpty {
                        self.forecastAreas = forecastAreas
                        self.forecastDetail = forecastAreas[0].content
                    }
                    print("Forecast content: \(self.forecastDetail)")
                } catch {
                    print(error)
                }
            }
    }
}
