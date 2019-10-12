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

    init(forecastDetail: String = "") {
        self.forecastDetail = forecastDetail
    }

    private(set) lazy var getData: () -> Void = {

        let url: String = getEnv("FORECAST API")!
        print("FORECAST API", url)
        AF.request(url)
            .validate(contentType: ["application/json"])
            .responseData { response in
                do {
                    let forecastArea = try JSONDecoder().decode([ForecastArea].self, from: response.data!)

                    if !forecastArea.isEmpty {
                        self.forecastDetail = forecastArea[0].content
                    }
                    print("Forecast content: \(self.forecastDetail)")
                } catch {
                    print(error)
                }
            }
    }
}
