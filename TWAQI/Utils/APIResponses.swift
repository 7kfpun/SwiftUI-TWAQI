//
//  APIResponses.swift
//  TWAQI
//
//  Created by kf on 1/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

struct PollutantsResponse: Decodable {
    let success: Bool
    let data: Pollutants

    private enum CodingKeys: String, CodingKey {
        case success
        case data
    }
}

struct AdResponse: Decodable {
    let success: Bool
    let data: CustomAd

    private enum CodingKeys: String, CodingKey {
        case success
        case data
    }
}
