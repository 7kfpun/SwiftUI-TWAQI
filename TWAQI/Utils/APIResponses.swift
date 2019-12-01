//
//  APIResponses.swift
//  TWAQI
//
//  Created by kf on 1/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

struct CountriesResponse: Decodable {
    let success: Bool
    let data: Countries

    private enum CodingKeys: String, CodingKey {
        case success
        case data
    }
}

struct NewStationsResponse: Decodable {
    let success: Bool
    let data: NewStations

    private enum CodingKeys: String, CodingKey {
        case success
        case data
    }
}
