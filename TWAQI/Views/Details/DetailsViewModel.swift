//
//  DetailsViewModel.swift
//  TWAQI
//
//  Created by kf on 13/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Alamofire
import Combine
import Foundation

class DetailsViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var station: Station

    @Published var historyPollutants: [HistoryPollutant] = [] {
        willSet { self.objectWillChange.send() }
    }

    init(station: Station, historyPollutants: [HistoryPollutant] = []) {
        self.station = station
        self.historyPollutants = historyPollutants
    }

    private(set) lazy var getData: () -> Void = {
        let url: String = getEnv("HISTORY API")!
        print("HISTORY API", url)
        let parameters: Parameters = [
            "station": self.station.nameLocal,
        ]

        AF.request(url, parameters: parameters)
            .validate(contentType: ["application/json"])
            .responseData { response in
                do {
                    let data = try JSONDecoder().decode([String: [HistoryPollutant]].self, from: response.data!)
                    self.historyPollutants = data["data"]!
                    print("HistoryPollutants: \(self.historyPollutants)")
                } catch {
                    print(error)
                }
            }
    }
}
