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
    case networkError
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
                    guard let data: Data = response.data else {
                        completionHandler(.failure(.networkError))
                        return
                    }

                    debugPrint(response)
                    let pollutants = try JSONDecoder().decode(Pollutants.self, from: data)
                    completionHandler(.success(pollutants))
                } catch {
                    print(error)
                    completionHandler(.failure(.networkError))
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
                    guard let data: Data = response.data else {
                        completionHandler(.failure(.networkError))
                        return
                    }

                    debugPrint(response)
                    let forecastAreas = try JSONDecoder().decode([ForecastArea].self, from: data)
                    completionHandler(.success(forecastAreas))
                } catch {
                    print(error)
                    completionHandler(.failure(.networkError))
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
                    guard let data: Data = response.data else {
                        completionHandler(.failure(.networkError))
                        return
                    }

                    debugPrint(response)
                    let jsonData = try JSONDecoder().decode([String: [HistoryPollutant]].self, from: data)
                    completionHandler(.success(jsonData["data"]!))
                } catch {
                    print(error)
                    completionHandler(.failure(.networkError))
                }
            }
    }

    static func getCustomAd(completionHandler: @escaping (Result<CustomAd, NetworkError>) -> Void) {
        guard let url = URL(string: getEnv("CUSTOM AD API")!) else {
            completionHandler(.failure(.badURL))
            return
        }

        AF.request(url)
            .validate(contentType: ["application/json"])
            .responseData { response in
                do {
                    guard let data: Data = response.data else {
                        completionHandler(.failure(.networkError))
                        return
                    }

                    debugPrint(response)
                    let customAd = try JSONDecoder().decode(CustomAd.self, from: data)
                    completionHandler(.success(customAd))
                } catch {
                    print(error)
                    completionHandler(.failure(.networkError))
                }
            }
    }
}
