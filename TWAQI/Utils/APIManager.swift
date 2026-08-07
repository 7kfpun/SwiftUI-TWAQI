//
//  APIManager.swift
//  TWAQI
//
//  Created by kf on 26/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Alamofire
import Foundation
import SwiftyJSON

enum NetworkError: Error {
    case badURL
    case networkError
}

struct APIManager {
    static let apiDomain = getEnv("ApiDomain")!
    static let apiEnpointCountries = getEnv("ApiEnpointCountries")!
    static let apiEnpointStations = getEnv("ApiEnpointStations")!

    static let apiEnpointCurrentPollutants = getEnv("ApiEnpointCurrentPollutants")!
    static let apiEnpointHistoricalPollutants = getEnv("ApiEnpointHistoricalPollutants")!

    // MARK: - V1 endpoints
    static func getCountries(completionHandler: @escaping (Result<Countries, NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)\(self.apiEnpointCountries)") else {
            completionHandler(.failure(.badURL))
            return
        }

        AF.request(url)
            .validate(contentType: ["application/json"])
            .responseJSON { (response) -> Void in
                let json = JSON(response.data as Any)
                debugPrint("getCountries.responseJSON: \(json)")
                if json["success"] == true {
                    var countries: Countries = []
                    for (_, countryJSON) in json["data"] {
                        let code = countryJSON["code"].string ?? ""
                        let nameEn = countryJSON["name"]["en"].string
                        let nameZh = countryJSON["name"]["zh"].string
                        let nameTh = countryJSON["name"]["th"].string
                        countries.append(Country(
                            id: countryJSON["id"].int ?? 0,
                            code: code,
                            lat: countryJSON["lat"].double ?? 0,
                            lon: countryJSON["lon"].double ?? 0,
                            zoom: countryJSON["zoom"].float ?? 0,
                            name: nameEn ?? nameZh ?? nameTh ?? code.uppercased(),
                            nameLocal: nameZh ?? nameTh ?? nameEn ?? code.uppercased()
                        ))
                    }
                    completionHandler(.success(countries))
                }
            }
    }

    static func getStations(countryCode: String, completionHandler: @escaping (Result<Stations, NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)\(self.apiEnpointStations)") else {
            completionHandler(.failure(.badURL))
            return
        }

        let parameters: Parameters = [
            "country": countryCode,
        ]

        AF.request(url, parameters: parameters)
            .validate(contentType: ["application/json"])
            .responseJSON { (response) -> Void in
                let json = JSON(response.data as Any)
                debugPrint("getStations.responseJSON: \(json)")
                if json["success"] == true {
                    var stations: Stations = []
                    for (_, stationJSON) in json["data"] {
                        stations.append(Station.make(from: stationJSON))
                    }
                    completionHandler(.success(stations))
                }
            }
    }

    static func getCurrentPollutants(countryCode: String, completionHandler: @escaping (Result<Pollutants, NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)\(self.apiEnpointCurrentPollutants)") else {
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
                    let pollutantsResponse = try JSONDecoder().decode(PollutantsResponse.self, from: data)
                    completionHandler(.success(pollutantsResponse.data))
                } catch {
                    print(error)
                    completionHandler(.failure(.networkError))
                }
            }
    }

    static func getCurrentPollutantsByStationId(stationId: String, completionHandler: @escaping (Result<Pollutants, NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)\(self.apiEnpointCurrentPollutants)") else {
            completionHandler(.failure(.badURL))
            return
        }

        let parameters: Parameters = [
            "station_id": stationId,
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
                    let pollutantsResponse = try JSONDecoder().decode(PollutantsResponse.self, from: data)
                    completionHandler(.success(pollutantsResponse.data))
                } catch {
                    print(error)
                    completionHandler(.failure(.networkError))
                }
            }
    }

    static func getHistoricalPollutants(stationId: Int, limit: Int = 24, completionHandler: @escaping (Result<[String: Any], NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)\(self.apiEnpointHistoricalPollutants)") else {
            completionHandler(.failure(.badURL))
            return
        }

        let parameters: Parameters = [
            "station_id": stationId,
            "limit": limit,
        ]

        AF.request(url, parameters: parameters)
            .validate(contentType: ["application/json"])
            .responseJSON { (response) -> Void in
                let json = JSON(response.data as Any)
                debugPrint("getHistoricalPollutants.responseJSON: \(json)")
                if json["success"] == true {
                    let station = Station.make(from: json["station"])

                    var historicalPollutants: HistoricalPollutants = []
                    for (_, historicalPollutantJSON) in json["data"] {
                        historicalPollutants.append(HistoricalPollutant(
                            aqi: historicalPollutantJSON["aqi"].double ?? 0,
                            pm25: historicalPollutantJSON["pm25"].double ?? 0,
                            pm10: historicalPollutantJSON["pm10"].double ?? 0,
                            no2: historicalPollutantJSON["no2"].double ?? 0,
                            so2: historicalPollutantJSON["so2"].double ?? 0,
                            co: historicalPollutantJSON["co"].double ?? 0,
                            o3: historicalPollutantJSON["o3"].double ?? 0,
                            windDirection: historicalPollutantJSON["wind_direction"].double ?? 0,
                            windSpeed: historicalPollutantJSON["wind_speed"].double ?? 0,
                            publishTime: historicalPollutantJSON["publish_time"].string ?? ""
                        ))
                    }

                    completionHandler(.success([
                        "station": station,
                        "data": historicalPollutants,
                    ]))
                }
            }
    }
}
