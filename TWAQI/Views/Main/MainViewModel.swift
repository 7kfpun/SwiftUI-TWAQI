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

    @Published var landmarks: [Landmark] = [] {
        willSet { self.objectWillChange.send() }
    }
    @Published var count: Int = 0 {
        willSet { self.objectWillChange.send() }
    }

    init(landmarks: [Landmark] = []) {
        self.landmarks = landmarks
    }

    private(set) lazy var getData: () -> Void = {
        self.landmarks = []

        let url: String = getEnv("AQI API")!

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let session = URLSession.shared
        let task = session.dataTask(with: request, completionHandler: { data, response, error -> Void in
            print(response!)

            do {
                let pollutants = try JSONDecoder().decode([Pollutant].self, from: data!)

                var landmarks: [Landmark] = []

                for pollutant in pollutants {
                    landmarks.append(
                        Landmark(
                            name: pollutant.siteName,
                            location: .init(
                                latitude: Double(pollutant.latitude)!,
                                longitude: Double(pollutant.longitude)!
                            ),
                            aqi: pollutant.aqi
                        )
                    )
                }

                self.landmarks = landmarks
                self.count = landmarks.count
                print("Total: \(landmarks.count), first item \(landmarks[0])")
            } catch {
                print(error)
            }
        })

        task.resume()
    }
}
