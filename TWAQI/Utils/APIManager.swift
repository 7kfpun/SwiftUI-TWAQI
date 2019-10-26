//
//  APIManager.swift
//  TWAQI
//
//  Created by kf on 26/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Alamofire
import Foundation

enum NetworkError: Error {
    case badURL
}

struct APIManager {
    static func getAQI(completionHandler: @escaping (Result<Pollutants, NetworkError>) -> Void) {
        guard let url = URL(string: getEnv("AQI API")!) else {
            completionHandler(.failure(.badURL))
            return
        }

        AF.request(url)
            .validate(contentType: ["application/json"])
            .responseData { response in
                do {
                    debugPrint(response)
                    let pollutants = try JSONDecoder().decode(Pollutants.self, from: response.data!)
                    completionHandler(.success(pollutants))
                } catch {
                    print(error)
                    completionHandler(.failure(.badURL))
                }
            }
    }

    static func getForecast(completionHandler: @escaping (Result<ForecastAreas, NetworkError>) -> Void) {
        guard let url = URL(string: getEnv("FORECAST API")!) else {
            completionHandler(.failure(.badURL))
            return
        }

        AF.request(url)
            .validate(contentType: ["application/json"])
            .responseData { response in
                do {
                    debugPrint(response)
                    let forecastAreas = try JSONDecoder().decode([ForecastArea].self, from: response.data!)
                    completionHandler(.success(forecastAreas))
                } catch {
                    print(error)
                    completionHandler(.failure(.badURL))
                }
            }
    }

    static func getHistory(nameLocal: String, completionHandler: @escaping (Result<HistoryPollutants, NetworkError>) -> Void) {
        guard let url = URL(string: getEnv("HISTORY API")!) else {
            completionHandler(.failure(.badURL))
            return
        }

        let parameters: Parameters = [
            "station": nameLocal,
        ]

        AF.request(url, parameters: parameters)
            .validate(contentType: ["application/json"])
            .responseData { response in
                do {
                    debugPrint(response)
                    let data = try JSONDecoder().decode([String: [HistoryPollutant]].self, from: response.data!)
                    completionHandler(.success(data["data"]!))
                } catch {
                    print(error)
                }
            }
    }
}
