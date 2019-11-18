//
//  ContentViewModel.swift
//  watch Extension
//
//  Created by kf on 18/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Combine
import Foundation

class ContentViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var station: Station?

    @Published var historyPollutants: [HistoryPollutant] = [] {
        willSet { self.objectWillChange.send() }
    }

    init(station: Station, historyPollutants: [HistoryPollutant] = []) {
        self.station = station
        self.historyPollutants = historyPollutants
    }

    private(set) lazy var getData: () -> Void = {
        guard let nameLocal = self.station?.nameLocal else {
            return
        }

        let api = getEnv("HISTORY API")!
        let endpoint = "?station=\(nameLocal)&limit=1"

        var urlString = (api + endpoint).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

        let url = URL(string: urlString)

        var request = URLRequest(url: url!)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let session = URLSession.shared
        let task = session.dataTask(with: request, completionHandler: { data, _, error -> Void in
            do {
                if let data = data {
                    let jsonResponse = try JSONDecoder().decode([String: [HistoryPollutant]].self, from: data)
                    self.historyPollutants = jsonResponse["data"]!
                    print("HistoryPollutant: \(self.historyPollutants)")
                }
            } catch {
                print(error)
            }
        })

        task.resume()
    }
}
