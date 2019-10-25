//
//  MainViewModel.swift
//  TWAQI
//
//  Created by kf on 2/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Alamofire
import Combine
import Foundation

class MainViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    @Published var pollutants: [Pollutant] = [] {
        willSet { self.objectWillChange.send() }
    }
    @Published var count: Int = 0 {
        willSet { self.objectWillChange.send() }
    }

    private(set) lazy var getData: () -> Void = {
        let url: String = getEnv("AQI API")!
        AF.request(url)
            .validate(contentType: ["application/json"])
            .responseData { response in
                do {
                    debugPrint(response)

                    let pollutants = try JSONDecoder().decode(Pollutants.self, from: response.data!)

                    self.pollutants = pollutants
                    self.count = pollutants.count
                    print("Total: \(pollutants.count), first item \(pollutants[0])")
                } catch {
                    print(error)
                }
            }
    }
}
