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
    /// Alamofire's default session waits 60 s for a response and has no
    /// overall limit, so on a flaky connection a screen could sit on its
    /// placeholder for minutes before falling back to the last good copy.
    /// 20 s matches the Directus requests.
    static let session: Session = {
        let configuration = URLSessionConfiguration.af.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return Session(configuration: configuration)
    }()

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

        session.request(url)
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
                } else {
                    // Without this an offline launch never called back.
                    completionHandler(.failure(.networkError))
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

        session.request(url, parameters: parameters)
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
                } else {
                    completionHandler(.failure(.networkError))
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

        session.request(url, parameters: parameters)
            .validate(contentType: ["application/json"])
            .responseData { response in
                debugPrint(response)
                // Every path calls back: transport/validation failure, an
                // undecodable body, or success. Only a decoded response is saved.
                switch response.result {
                case .success(let data):
                    do {
                        let pollutantsResponse = try JSONDecoder().decode(PollutantsResponse.self, from: data)
                        PollutantCache.shared.save(countryCode: countryCode, response: data)
                        completionHandler(.success(pollutantsResponse.data))
                    } catch {
                        print(error)
                        completionHandler(.failure(.networkError))
                    }
                case .failure(let error):
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

        session.request(url, parameters: parameters)
            .validate(contentType: ["application/json"])
            .responseData { response in
                debugPrint(response)
                // Every path calls back: transport/validation failure, an
                // undecodable body, or success. Only a decoded response is saved.
                switch response.result {
                case .success(let data):
                    do {
                        let pollutantsResponse = try JSONDecoder().decode(PollutantsResponse.self, from: data)
                        PollutantCache.shared.saveStations(response: data)
                        completionHandler(.success(pollutantsResponse.data))
                    } catch {
                        print(error)
                        completionHandler(.failure(.networkError))
                    }
                case .failure(let error):
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

        session.request(url, parameters: parameters)
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
                } else {
                    // Without this a failed request never called back, and the
                    // map timeline's request queue waited on it for good.
                    completionHandler(.failure(.networkError))
                }
            }
    }
}
