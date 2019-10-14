//
//  DetailsHistoryViewModel.swift
//  TWAQI
//
//  Created by kf on 13/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Alamofire
import Combine
import Foundation

class DetailsHistoryViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    @Published var historytPollutants: [HistoryPollutant] = [] {
        willSet { self.objectWillChange.send() }
    }

    init(historytPollutants: [HistoryPollutant] = []) {
        self.historytPollutants = historytPollutants
    }

    private(set) lazy var getData: () -> Void = {
        let url: String = getEnv("HISTORY API")!
        print("HISTORY API", url)
        let parameters: Parameters = [
            "station": "苗栗",
        ]

        AF.request(url, parameters: parameters)
            .validate(contentType: ["application/json"])
            .responseData { response in
                do {
                    let data = try JSONDecoder().decode([String: [HistoryPollutant]].self, from: response.data!)

                    self.historytPollutants = data["data"]!
                    print("HistoryPollutants: \(self.historytPollutants)")
                } catch {
                    print(error)
                }
            }
    }
}
