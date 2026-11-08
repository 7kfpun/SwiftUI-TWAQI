//
//  APIManager.swift
//  TWAQI
//
//  Created by kf on 26/10/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

enum NetworkError: Error {
    case badURL
    case networkError
}

struct APIManager {
    /// URLSession's default waits 60 s for a response and has no overall
    /// limit (7 days), so on a flaky connection a screen could sit on its
    /// placeholder for minutes before falling back to the last good copy.
    /// 20 s matches the Directus requests.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    /// GET `url` with `query`, and call back on the main queue (as Alamofire
    /// did) with the body of a 2xx `application/json` response; anything else
    /// is `.networkError`.
    static func get(_ url: URL, query: [String: String] = [:], completion: @escaping (Result<Data, NetworkError>) -> Void) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            completion(.failure(.badURL))
            return
        }
        if !query.isEmpty {
            let extra = query.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            components.queryItems = (components.queryItems ?? []) + extra
        }
        guard let requestURL = components.url else {
            completion(.failure(.badURL))
            return
        }

        session.dataTask(with: requestURL) { data, response, error in
            let result: Result<Data, NetworkError>
            if let error {
                AppLog.network.error("request failed: \(error.localizedDescription)")
                result = .failure(.networkError)
            } else if let data, let http = response as? HTTPURLResponse, isJSON(http) {
                result = .success(data)
            } else {
                result = .failure(.networkError)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// The status/content-type check `.validate(contentType:)` did.
    static func isJSON(_ response: HTTPURLResponse) -> Bool {
        guard (200..<300).contains(response.statusCode) else { return false }
        let type = response.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";").first?
            .trimmingCharacters(in: .whitespaces).lowercased()
        return type == "application/json"
    }

    /// The decoded body when it is a JSON object with `"success": true`.
    static func successObject(_ data: Data) -> [String: Any]? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["success"] as? Bool == true else { return nil }
        return object
    }

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

        get(url) { result in
            // Without the failure branches an offline launch never called back.
            guard case .success(let data) = result,
                  let json = successObject(data) else {
                completionHandler(.failure(.networkError))
                return
            }
            let items = json["data"] as? [[String: Any]] ?? []
            let countries: Countries = items.map { item in
                let code = item.string("code") ?? ""
                let name = item.object("name")
                let nameEn = name.string("en")
                let nameZh = name.string("zh")
                let nameTh = name.string("th")
                return Country(
                    id: item.int("id") ?? 0,
                    code: code,
                    lat: item.double("lat") ?? 0,
                    lon: item.double("lon") ?? 0,
                    zoom: item.float("zoom") ?? 0,
                    name: nameEn ?? nameZh ?? nameTh ?? code.uppercased(),
                    nameLocal: nameZh ?? nameTh ?? nameEn ?? code.uppercased()
                )
            }
            completionHandler(.success(countries))
        }
    }

    static func getStations(countryCode: String, completionHandler: @escaping (Result<Stations, NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)\(self.apiEnpointStations)") else {
            completionHandler(.failure(.badURL))
            return
        }

        get(url, query: ["country": countryCode]) { result in
            guard case .success(let data) = result,
                  let json = successObject(data) else {
                completionHandler(.failure(.networkError))
                return
            }
            let items = json["data"] as? [[String: Any]] ?? []
            completionHandler(.success(items.map { Station.make(from: $0) }))
        }
    }

    static func getCurrentPollutants(countryCode: String, completionHandler: @escaping (Result<Pollutants, NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)\(self.apiEnpointCurrentPollutants)") else {
            completionHandler(.failure(.badURL))
            return
        }

        get(url, query: ["country": countryCode]) { result in
            // Every path calls back: transport/validation failure, an
            // undecodable body, or success. Only a decoded response is saved.
            switch result {
            case .success(let data):
                do {
                    let pollutantsResponse = try JSONDecoder().decode(PollutantsResponse.self, from: data)
                    PollutantCache.shared.save(countryCode: countryCode, response: data)
                    completionHandler(.success(pollutantsResponse.data))
                } catch {
                    AppLog.network.error("undecodable pollutants response: \(error.localizedDescription)")
                    completionHandler(.failure(.networkError))
                }
            case .failure(let error):
                completionHandler(.failure(error))
            }
        }
    }

    static func getCurrentPollutantsByStationId(stationId: String, completionHandler: @escaping (Result<Pollutants, NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)\(self.apiEnpointCurrentPollutants)") else {
            completionHandler(.failure(.badURL))
            return
        }

        get(url, query: ["station_id": stationId]) { result in
            switch result {
            case .success(let data):
                do {
                    let pollutantsResponse = try JSONDecoder().decode(PollutantsResponse.self, from: data)
                    PollutantCache.shared.saveStations(response: data)
                    completionHandler(.success(pollutantsResponse.data))
                } catch {
                    AppLog.network.error("undecodable pollutants response: \(error.localizedDescription)")
                    completionHandler(.failure(.networkError))
                }
            case .failure(let error):
                completionHandler(.failure(error))
            }
        }
    }

    static func getHistoricalPollutants(stationId: Int, limit: Int = 24, completionHandler: @escaping (Result<[String: Any], NetworkError>) -> Void) {
        guard let url = URL(string: "\(self.apiDomain)\(self.apiEnpointHistoricalPollutants)") else {
            completionHandler(.failure(.badURL))
            return
        }

        get(url, query: ["station_id": String(stationId), "limit": String(limit)]) { result in
            // Without the failure branches a failed request never called back,
            // and the map timeline's request queue waited on it for good.
            guard case .success(let data) = result,
                  let json = successObject(data) else {
                completionHandler(.failure(.networkError))
                return
            }
            let station = Station.make(from: json.object("station"))
            let items = json["data"] as? [[String: Any]] ?? []
            let historicalPollutants: HistoricalPollutants = items.map { item in
                HistoricalPollutant(
                    aqi: item.double("aqi") ?? 0,
                    pm25: item.double("pm25") ?? 0,
                    pm10: item.double("pm10") ?? 0,
                    no2: item.double("no2") ?? 0,
                    so2: item.double("so2") ?? 0,
                    co: item.double("co") ?? 0,
                    o3: item.double("o3") ?? 0,
                    windDirection: item.double("wind_direction") ?? 0,
                    windSpeed: item.double("wind_speed") ?? 0,
                    publishTime: item.string("publish_time") ?? ""
                )
            }
            completionHandler(.success([
                "station": station,
                "data": historicalPollutants,
            ]))
        }
    }
}
