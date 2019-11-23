//
//  HistoryPollutantManager.swift
//  watch Extension
//
//  Created by kf on 23/11/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Alamofire
import Foundation

enum NetworkError: Error {
    case badURL
    case networkError
}

struct HistoryPollutantManager {
    static func getHistory(nameLocal: String, completionHandler: @escaping (Result<HistoryPollutants, NetworkError>) -> Void) {
        guard let url = URL(string: getEnv("HISTORY API")!) else {
            completionHandler(.failure(.badURL))
            return
        }

        let parameters: Parameters = [
            "station": nameLocal,
            "limit": 1,
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
}
