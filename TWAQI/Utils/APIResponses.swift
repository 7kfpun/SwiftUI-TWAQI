//
//  APIResponses.swift
//  TWAQI
//
//  Created by kf on 1/12/19.
//  Copyright © 2019 kf. All rights reserved.
//

import Foundation

struct NewPollutantsResponse: Decodable {
    let success: Bool
    let data: NewPollutants

    private enum CodingKeys: String, CodingKey {
        case success
        case data
    }
}
