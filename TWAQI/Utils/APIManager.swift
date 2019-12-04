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
    static let apiDomain = getEnv("ApiDomain")!

    // MARK: - V1 endpoints
    static func getCountries(completionHandler: @escaping (Result<Countries, NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)/v1/countries") else {
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
                    let countriesResponse = try JSONDecoder().decode(CountriesResponse.self, from: data)
                    completionHandler(.success(countriesResponse.data))
                } catch {
                    print(error)
                    completionHandler(.failure(.networkError))
                }
            }
    }

    static func getStations(countryCode: String, completionHandler: @escaping (Result<NewStations, NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)/v1/stations") else {
            completionHandler(.failure(.badURL))
            return
        }

        let parameters: Parameters = [
            "country": countryCode,
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
                    let newStationsResponse = try JSONDecoder().decode(NewStationsResponse.self, from: data)
                    completionHandler(.success(newStationsResponse.data))
                } catch {
                    print(error)
                    completionHandler(.failure(.networkError))
                }
            }
    }

    static func getCurrentPollutants(countryCode: String, completionHandler: @escaping (Result<NewPollutants, NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)/v1/current-pollutants") else {
            completionHandler(.failure(.badURL))
            return
        }

        let parameters: Parameters = [
            "country": countryCode,
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
                    let newPollutantsResponse = try JSONDecoder().decode(NewPollutantsResponse.self, from: data)
                    completionHandler(.success(newPollutantsResponse.data))
                } catch {
                    print(error)
                    completionHandler(.failure(.networkError))
                }
            }
    }

    static func getCurrentPollutantsByStationIds(stationIds: String, completionHandler: @escaping (Result<NewPollutants, NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)/v1/current-pollutants") else {
            completionHandler(.failure(.badURL))
            return
        }

        let parameters: Parameters = [
            "station_ids": stationIds,
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
                    let newPollutantsResponse = try JSONDecoder().decode(NewPollutantsResponse.self, from: data)
                    completionHandler(.success(newPollutantsResponse.data))
                } catch {
                    print(error)
                    completionHandler(.failure(.networkError))
                }
            }
    }

    static func getHourlyHistorical(stationId: Int, limit: Int = 24, completionHandler: @escaping (Result<[String: Any], NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)/v1/historical-pollutants") else {
            completionHandler(.failure(.badURL))
            return
        }

        let parameters: Parameters = [
            "station_id": stationId,
            "limit": limit,
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
                    let historicalPollutantsResponse = try JSONDecoder().decode(HistoricalPollutantsResponse.self, from: data)
                    print("stationstationstation", historicalPollutantsResponse.station)
                    completionHandler(.success([
                        "station": historicalPollutantsResponse.station,
                        "data": historicalPollutantsResponse.data,
                    ]))
                } catch {
                    print(error)
                    completionHandler(.failure(.networkError))
                }
            }
    }

    // MARK: - Legacy endpoints
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

    static func getHistory(nameLocal: String, limit: Int = 24, completionHandler: @escaping (Result<HistoryPollutants, NetworkError>) -> Void) {
        guard let url = URL(string: getEnv("HISTORY API")!) else {
            completionHandler(.failure(.badURL))
            return
        }

        let parameters: Parameters = [
            "station": nameLocal,
            "limit": limit,
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

    // MARK: - Other endpoints
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
